import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

SUPPORTED = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}


def largest_component(mask: np.ndarray) -> np.ndarray:
    num, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    if num <= 1:
        return mask
    idx = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (labels == idx).astype(np.uint8)


def make_mask(img_bgr: np.ndarray, strict: bool) -> np.ndarray:
    h, w = img_bgr.shape[:2]
    mask = np.zeros((h, w), np.uint8)
    bg = np.zeros((1, 65), np.float64)
    fg = np.zeros((1, 65), np.float64)

    rect = (int(w * 0.18), int(h * 0.14), int(w * 0.64), int(h * 0.72)) if strict else (int(w * 0.15), int(h * 0.12), int(w * 0.70), int(h * 0.76))
    cv2.grabCut(img_bgr, mask, rect, bg, fg, 7 if strict else 6, cv2.GC_INIT_WITH_RECT)
    bin_mask = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 1, 0).astype(np.uint8)

    k = np.ones((5, 5), np.uint8)
    bin_mask = cv2.morphologyEx(bin_mask, cv2.MORPH_OPEN, k)
    bin_mask = cv2.morphologyEx(bin_mask, cv2.MORPH_CLOSE, k)
    if strict:
        bin_mask = cv2.erode(bin_mask, np.ones((5, 5), np.uint8), iterations=1)

    bin_mask = largest_component(bin_mask)

    if strict:
        yy, xx = np.indices((h, w))
        cx, cy = w / 2.0, h / 2.0
        nx = (xx - cx) / (0.68 * w)
        ny = (yy - cy) / (0.68 * h)
        center_ellipse = (nx * nx + ny * ny) <= 1.0
        bin_mask = (bin_mask & center_ellipse.astype(np.uint8)).astype(np.uint8)
        bin_mask = largest_component(bin_mask)

    return bin_mask


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", required=True)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--mask-dir", required=True)
    ap.add_argument("--stats-json", required=True)
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    inp = Path(args.input_dir)
    out = Path(args.output_dir)
    mdir = Path(args.mask_dir)
    out.mkdir(parents=True, exist_ok=True)
    mdir.mkdir(parents=True, exist_ok=True)

    stats = {"input_count": 0, "accepted_count": 0, "rejected_count": 0, "rejections": []}

    idx = 1
    for p in sorted(inp.rglob("*")):
        if not p.is_file():
            continue
        stats["input_count"] += 1
        if p.suffix.lower() not in SUPPORTED:
            stats["rejected_count"] += 1
            stats["rejections"].append({"file": str(p), "reason": "unsupported format"})
            continue

        try:
            with Image.open(p) as im:
                im = ImageOps.exif_transpose(im).convert("RGB")
                rgb = np.array(im)

            bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
            mask = make_mask(bgr, strict=args.strict)

            name = f"img_{idx:04d}.jpg"
            mask_name = f"img_{idx:04d}.png"
            Image.fromarray(rgb).save(out / name, format="JPEG", quality=95, optimize=True)
            Image.fromarray((mask * 255).astype(np.uint8)).save(mdir / mask_name, format="PNG")

            idx += 1
            stats["accepted_count"] += 1
        except Exception as exc:
            stats["rejected_count"] += 1
            stats["rejections"].append({"file": str(p), "reason": str(exc)})

    Path(args.stats_json).write_text(json.dumps(stats, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
