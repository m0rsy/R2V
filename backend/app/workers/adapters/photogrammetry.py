from __future__ import annotations

import tempfile
from pathlib import Path

from app.core.config import settings
from app.services import photogrammetry_modal as modal_pg

# Image extensions accepted as reconstruction inputs.
_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def reconstruct_from_images(image_dir: Path, out_glb: Path) -> None:
    """Reconstruct a 3D mesh (GLB) from a folder of input images via Modal.

    Honesty contract:
      * Never writes a fake/placeholder GLB.
      * The reconstruction runs on the deployed Modal photogrammetry app — the
        same system used by the HTTP /photogrammetry routes. If Modal is
        unreachable or produces no model, this raises a clear error so the scan
        job fails with a useful message (rather than emitting a placeholder).
    """
    images = [p for p in sorted(image_dir.glob("*")) if p.suffix.lower() in _IMAGE_EXTS]
    if not images:
        raise RuntimeError(f"No input images found in {image_dir} for reconstruction")
    if len(images) < settings.photogrammetry_min_images:
        raise RuntimeError(
            f"Need at least {settings.photogrammetry_min_images} images to "
            f"reconstruct; got {len(images)}"
        )

    # Forward the images to Modal (blocking) and receive a ZIP of outputs.
    try:
        zip_bytes, _run_id = modal_pg.reconstruct(
            images,
            texture_mode=settings.photogrammetry_texture_mode,
            no_strict_mask=settings.photogrammetry_no_strict_mask,
            timeout_s=settings.photogrammetry_modal_timeout_s,
        )
    except modal_pg.PhotogrammetryModalError as exc:
        raise RuntimeError(str(exc)) from exc

    out_glb.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        extract_dir = Path(td)
        modal_pg.extract_zip(zip_bytes, extract_dir)
        model = modal_pg.find_primary_model(extract_dir)
        if model is None or model.suffix.lower() != ".glb":
            # The pipeline always emits a GLB; if it didn't, fail honestly.
            glb = next((p for p in extract_dir.rglob("*.glb") if p.is_file()), None)
            if glb is None:
                raise RuntimeError(
                    "Modal reconstruction finished but produced no GLB output"
                )
            model = glb
        out_glb.write_bytes(model.read_bytes())

    if not out_glb.exists() or out_glb.stat().st_size <= 0:
        raise RuntimeError("Reconstruction finished but produced no GLB output")
