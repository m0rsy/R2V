"""Shared client for the deployed Modal photogrammetry app.

The backend is a proxy/controller in front of the Modal app. This module is the
single place that knows the Modal contract so both the HTTP-facing job store
(``app.services.photogrammetry_jobs``) and the Celery scan worker
(``app.workers.adapters.photogrammetry``) talk to Modal the same way.

Verified live contract (see ``GET /openapi.json`` on the deployed app):

    POST /reconstruct   multipart/form-data
        files          : array of image files (and/or a .zip of images)  [required]
        texture_mode   : "vertexcolor" | "openmvs"   (default "vertexcolor")
        no_strict_mask : bool                          (default false)
      -> BLOCKING. On success returns a binary ZIP (``reconstruction.zip``)
         containing every output (extracted images, OBJ/PLY/GLB, reports, ...).
      There is no async status endpoint and no per-file download URL: the whole
      result is the ZIP body, so callers extract it and cache the files.
"""

from __future__ import annotations

import io
import mimetypes
import shutil
import zipfile
from pathlib import Path
from typing import Iterable

import httpx

from app.core.config import settings

# Image suffixes the Modal pipeline accepts as reconstruction inputs.
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
# Model outputs we consider a usable reconstruction result, best first.
MODEL_SUFFIXES_PRIORITY = (".glb", ".obj", ".ply")


class PhotogrammetryModalError(RuntimeError):
    """Raised when the Modal photogrammetry app is unreachable, misconfigured,
    or returns an error instead of a reconstruction package."""


def _base_url() -> str:
    url = (settings.photogrammetry_modal_api_url or "").strip()
    if not url:
        raise PhotogrammetryModalError(
            "Photogrammetry Modal endpoint is not configured. Set "
            "PHOTOGRAMMETRY_MODAL_API_URL to the deployed Modal app URL."
        )
    return url.rstrip("/")


def _auth_headers() -> dict:
    # The Modal app may optionally enforce R2V_API_TOKEN, mirroring the AI app.
    token = settings.r2v_api_token.strip()
    return {"Authorization": f"Bearer {token}"} if token else {}


def _error_detail(resp: httpx.Response) -> str:
    try:
        body = resp.json()
        if isinstance(body, dict):
            detail = body.get("detail") or body.get("error") or body.get("message")
            if detail:
                return str(detail)[:1000]
    except Exception:
        pass
    return (resp.text or "").strip()[:1000] or resp.reason_phrase


def reconstruct(
    image_paths: Iterable[str | Path],
    *,
    texture_mode: str | None = None,
    no_strict_mask: bool | None = None,
    timeout_s: int | None = None,
) -> tuple[bytes, str | None]:
    """Forward images to Modal ``POST /reconstruct`` and return ``(zip_bytes, run_id)``.

    Blocks until the Modal pipeline finishes (up to ``timeout_s``). Raises
    ``PhotogrammetryModalError`` on any failure (never returns a placeholder).
    """
    paths = [Path(p) for p in image_paths]
    if not paths:
        raise PhotogrammetryModalError("No images were provided for reconstruction")

    texture_mode = (texture_mode or settings.photogrammetry_texture_mode or "vertexcolor").strip()
    if no_strict_mask is None:
        no_strict_mask = settings.photogrammetry_no_strict_mask
    timeout_s = timeout_s or settings.photogrammetry_modal_timeout_s

    url = f"{_base_url()}/reconstruct"
    data = {
        "texture_mode": texture_mode,
        "no_strict_mask": str(bool(no_strict_mask)).lower(),
    }

    handles: list = []
    try:
        files = []
        for path in paths:
            if not path.is_file():
                continue
            handle = path.open("rb")
            handles.append(handle)
            mime, _ = mimetypes.guess_type(path.name)
            files.append(("files", (path.name, handle, mime or "image/jpeg")))
        if not files:
            raise PhotogrammetryModalError("None of the provided image paths exist on disk")

        try:
            with httpx.Client(
                timeout=httpx.Timeout(timeout_s, connect=60.0),
                follow_redirects=True,
            ) as client:
                resp = client.post(url, files=files, data=data, headers=_auth_headers())
        except httpx.HTTPError as exc:
            raise PhotogrammetryModalError(
                f"Could not reach the photogrammetry Modal app at {url}: {exc}"
            ) from exc
    finally:
        for handle in handles:
            try:
                handle.close()
            except Exception:
                pass

    if resp.status_code >= 400:
        raise PhotogrammetryModalError(
            f"Modal photogrammetry returned {resp.status_code}: {_error_detail(resp)}"
        )

    run_id = (
        resp.headers.get("x-run-id")
        or resp.headers.get("x-run")
        or None
    )
    content_type = resp.headers.get("content-type", "").lower()

    # Primary contract: a binary ZIP of outputs.
    if "zip" in content_type or "octet-stream" in content_type or not content_type:
        if not resp.content:
            raise PhotogrammetryModalError("Modal photogrammetry returned an empty response")
        return resp.content, run_id

    # Defensive fallback: a JSON body that points at a downloadable ZIP. The live
    # app returns a ZIP directly, but this keeps us robust if the contract gains
    # an async/URL shape later.
    if "application/json" in content_type:
        try:
            payload = resp.json()
        except Exception as exc:
            raise PhotogrammetryModalError(
                "Modal photogrammetry returned an unexpected JSON body"
            ) from exc
        if isinstance(payload, dict):
            status = str(payload.get("status", "")).lower()
            if status in {"failed", "error"}:
                raise PhotogrammetryModalError(
                    f"Modal photogrammetry failed: {payload.get('error') or payload.get('detail') or 'unknown error'}"
                )
            zip_url = (
                payload.get("zip_url")
                or payload.get("download_url")
                or payload.get("result_url")
            )
            run_id = payload.get("run_id") or payload.get("job_id") or run_id
            if zip_url:
                with httpx.Client(
                    timeout=httpx.Timeout(timeout_s, connect=60.0), follow_redirects=True
                ) as client:
                    dl = client.get(str(zip_url), headers=_auth_headers())
                dl.raise_for_status()
                return dl.content, (str(run_id) if run_id else None)
        raise PhotogrammetryModalError(
            "Modal photogrammetry returned JSON without a downloadable result"
        )

    # Anything else: treat the body as the package bytes (best effort).
    if resp.content:
        return resp.content, run_id
    raise PhotogrammetryModalError(
        f"Modal photogrammetry returned an unexpected response (content-type={content_type!r})"
    )


def extract_zip(zip_bytes: bytes, dest_dir: str | Path) -> list[str]:
    """Safely extract a reconstruction ZIP into ``dest_dir``.

    Path traversal is prevented (no absolute paths, no ``..`` escapes). Returns
    the list of extracted file paths relative to ``dest_dir`` (posix form).
    """
    dest = Path(dest_dir)
    dest.mkdir(parents=True, exist_ok=True)
    dest_resolved = dest.resolve()
    saved: list[str] = []

    try:
        archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except zipfile.BadZipFile as exc:
        raise PhotogrammetryModalError(
            "Modal photogrammetry response was not a valid ZIP archive"
        ) from exc

    with archive:
        for member in archive.infolist():
            if member.is_dir():
                continue
            parts = [p for p in Path(member.filename).parts if p not in ("", "..", "/", "\\")]
            # Drop any drive/anchor components (e.g. "C:\\").
            parts = [p for p in parts if not p.endswith(":")]
            if not parts:
                continue
            safe_rel = Path(*parts)
            target = dest / safe_rel
            target_resolved = target.resolve()
            if dest_resolved != target_resolved and dest_resolved not in target_resolved.parents:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as src, target.open("wb") as out:
                shutil.copyfileobj(src, out)
            saved.append(safe_rel.as_posix())

    if not saved:
        raise PhotogrammetryModalError("Modal photogrammetry ZIP contained no files")
    return saved


def find_primary_model(dir_path: str | Path) -> Path | None:
    """Return the best model file (GLB preferred) under ``dir_path``, if any."""
    root = Path(dir_path)
    candidates = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in MODEL_SUFFIXES_PRIORITY]
    if not candidates:
        return None

    def _score(path: Path) -> tuple[int, str]:
        try:
            order = MODEL_SUFFIXES_PRIORITY.index(path.suffix.lower())
        except ValueError:
            order = len(MODEL_SUFFIXES_PRIORITY)
        return order, path.name

    return sorted(candidates, key=_score)[0]
