from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from io import BytesIO
from threading import Lock
from typing import Any

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

from rembg import remove as rembg_remove, new_session

from app.config import BG_REMOVE_MODEL, BG_ALPHA_MATTING, BG_FAST_WHITE_BACKGROUND


@dataclass
class BgRemoveResult:
    rgba_png_bytes: bytes
    composited_rgb_png_bytes: bytes


_REMBG_SESSION: Any | None = None
_REMBG_LOCK = Lock()


def _get_rembg_session():
    global _REMBG_SESSION

    if _REMBG_SESSION is not None:
        return _REMBG_SESSION

    with _REMBG_LOCK:
        if _REMBG_SESSION is None:
            print(f"[bg_remove] Loading rembg session: {BG_REMOVE_MODEL}")
            _REMBG_SESSION = new_session(BG_REMOVE_MODEL)
        return _REMBG_SESSION


def _is_light_uniform_bg(rgb: np.ndarray, thr_mean: int = 235, thr_std: float = 18.0) -> bool:
    h, w = rgb.shape[:2]
    b = 12
    border = np.concatenate([
        rgb[:b, :, :].reshape(-1, 3),
        rgb[-b:, :, :].reshape(-1, 3),
        rgb[:, :b, :].reshape(-1, 3),
        rgb[:, -b:, :].reshape(-1, 3),
    ], axis=0)
    m = border.mean(axis=0)
    s = border.std(axis=0).mean()
    return bool((m.min() >= thr_mean) and (s <= thr_std))


def _estimate_bg_color(rgb: np.ndarray) -> np.ndarray:
    h, w = rgb.shape[:2]
    b = 12
    border = np.concatenate([
        rgb[:b, :, :].reshape(-1, 3),
        rgb[-b:, :, :].reshape(-1, 3),
        rgb[:, :b, :].reshape(-1, 3),
        rgb[:, -b:, :].reshape(-1, 3),
    ], axis=0)
    return np.median(border, axis=0)


def _floodfill_bg_mask(rgb: np.ndarray, bg: np.ndarray, tol: int = 55) -> np.ndarray:
    h, w = rgb.shape[:2]
    visited = np.zeros((h, w), dtype=np.uint8)
    mask = np.zeros((h, w), dtype=np.uint8)
    bg16 = bg.astype(np.int16)

    def _close(i: int, j: int) -> bool:
        return int(np.max(np.abs(rgb[i, j].astype(np.int16) - bg16))) <= tol

    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        q.append((0, x))
        q.append((h - 1, x))

    for y in range(h):
        q.append((y, 0))
        q.append((y, w - 1))

    while q:
        i, j = q.popleft()

        if visited[i, j]:
            continue

        visited[i, j] = 1

        if not _close(i, j):
            continue

        mask[i, j] = 1

        if i > 0:
            q.append((i - 1, j))
        if i < h - 1:
            q.append((i + 1, j))
        if j > 0:
            q.append((i, j - 1))
        if j < w - 1:
            q.append((i, j + 1))

    return mask


def _pad_bbox(
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    w: int,
    h: int,
    pad_px: int,
) -> tuple[int, int, int, int]:
    return (
        max(0, x0 - pad_px),
        max(0, y0 - pad_px),
        min(w, x1 + pad_px),
        min(h, y1 + pad_px),
    )


def _place_on_square_and_resize(
    rgb_img: Image.Image,
    out_size: int,
    pad_ratio: float,
) -> Image.Image:
    rgb = np.array(rgb_img)
    fg = np.where(np.max(255 - rgb, axis=2) > 3)

    if fg[0].size == 0:
        return rgb_img.resize((out_size, out_size), Image.LANCZOS)

    y0, y1 = int(fg[0].min()), int(fg[0].max()) + 1
    x0, x1 = int(fg[1].min()), int(fg[1].max()) + 1
    h, w = rgb.shape[:2]

    bw, bh = x1 - x0, y1 - y0
    pad_px = int(max(bw, bh) * pad_ratio)
    x0, y0, x1, y1 = _pad_bbox(x0, y0, x1, y1, w, h, pad_px)

    crop = rgb_img.crop((x0, y0, x1, y1))
    cw, ch = crop.size
    side = max(max(cw, ch), 8)

    canvas = Image.new("RGB", (side, side), (255, 255, 255))
    canvas.paste(crop, ((side - cw) // 2, (side - ch) // 2))

    return canvas.resize((out_size, out_size), Image.LANCZOS)


def remove_bg_and_compose_white(
    img_bytes: bytes,
    pad_ratio: float = 0.12,
    out_size: int = 512,
    bg_tol: int = 55,
    edge_soften_radius: float = 1.5,
    enhance: bool = False,
    enhance_contrast: float = 1.01,
    enhance_sharp: float = 1.02,
) -> BgRemoveResult:
    orig = Image.open(BytesIO(img_bytes)).convert("RGB")
    rgb = np.array(orig)

    if BG_FAST_WHITE_BACKGROUND and _is_light_uniform_bg(rgb):
        bg = _estimate_bg_color(rgb)
        bg_mask = _floodfill_bg_mask(rgb, bg=bg, tol=int(bg_tol))

        mask_img = Image.fromarray((bg_mask * 255).astype(np.uint8), mode="L")
        mask_soft = mask_img.filter(ImageFilter.GaussianBlur(radius=float(edge_soften_radius)))
        alpha = (np.array(mask_soft).astype(np.float32) / 255.0)[..., None]

        white = np.full_like(rgb, 255, dtype=np.uint8)

        blended = (
            rgb.astype(np.float32) * (1.0 - alpha)
            + white.astype(np.float32) * alpha
        ).clip(0, 255).astype(np.uint8)

        cleaned = Image.fromarray(blended, mode="RGB")

        if enhance:
            cleaned = ImageEnhance.Contrast(cleaned).enhance(float(enhance_contrast))
            cleaned = ImageEnhance.Sharpness(cleaned).enhance(float(enhance_sharp))

        final_rgb = _place_on_square_and_resize(
            cleaned,
            out_size=out_size,
            pad_ratio=pad_ratio,
        )

        rgba = final_rgb.convert("RGBA")

        buf_rgba = BytesIO()
        rgba.save(buf_rgba, format="PNG")

        buf_rgb = BytesIO()
        final_rgb.save(buf_rgb, format="PNG")

        return BgRemoveResult(
            rgba_png_bytes=buf_rgba.getvalue(),
            composited_rgb_png_bytes=buf_rgb.getvalue(),
        )

    session = _get_rembg_session()

    rgba_bytes = rembg_remove(
        img_bytes,
        session=session,
        alpha_matting=BG_ALPHA_MATTING,
        alpha_matting_foreground_threshold=245,
        alpha_matting_background_threshold=8,
        alpha_matting_erode_size=10,
    )

    rgba = Image.open(BytesIO(rgba_bytes)).convert("RGBA")

    white_bg = Image.new("RGB", rgba.size, (255, 255, 255))
    comp = Image.alpha_composite(white_bg.convert("RGBA"), rgba).convert("RGB")

    if enhance:
        comp = ImageEnhance.Contrast(comp).enhance(float(enhance_contrast))
        comp = ImageEnhance.Sharpness(comp).enhance(float(enhance_sharp))

    comp = _place_on_square_and_resize(
        comp,
        out_size=out_size,
        pad_ratio=pad_ratio,
    )

    rgba2 = comp.convert("RGBA")

    buf_rgba = BytesIO()
    rgba2.save(buf_rgba, format="PNG")

    buf_rgb = BytesIO()
    comp.save(buf_rgb, format="PNG")

    return BgRemoveResult(
        rgba_png_bytes=buf_rgba.getvalue(),
        composited_rgb_png_bytes=buf_rgb.getvalue(),
    )