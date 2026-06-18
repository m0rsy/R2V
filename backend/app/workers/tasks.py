from __future__ import annotations

import base64
import datetime as dt
import mimetypes
import tempfile
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models.jobs import AIJob, ScanJob
from app.db.session import SessionLocal
from app.services import notifications as notify
from app.services.s3 import s3
from app.workers.adapters.model_gen import image_to_3d, prompt_to_3d, voice_to_3d
from app.workers.adapters.photogrammetry import reconstruct_from_images
from app.workers.adapters.repair import repair_mesh
from app.workers.celery_app import celery_app


def _db() -> Session:
    return SessionLocal()


def _mark_failed(job, err: str, db: Session) -> None:
    job.status = "failed"
    job.error = err
    job.stage = "failed"
    job.message = err
    job.updated_at = dt.datetime.now(dt.timezone.utc)
    db.commit()
    # Best-effort in-app notification (own session so it can't poison `job`).
    if isinstance(job, ScanJob):
        notify.notify_scan_failed(None, job.user_id, job.id, err)
    else:
        notify.notify_ai_job_failed(None, job.user_id, job.id, err)


# Coarse stage -> progress fallback used only when Modal omits a numeric value.
_STAGE_PROGRESS = {
    "queued": 0,
    "starting": 5,
    "preparing": 5,
    "text_to_image": 15,
    "image_ready": 30,
    "background_removal": 35,
    "image_to_mesh": 45,
    "mesh_ready": 65,
    "texturing": 75,
    "finalizing": 95,
    "done": 100,
    "succeeded": 100,
}


def _make_progress_writer(job, db: Session):
    """Build a best-effort sink that mirrors Modal's live progress/stage/message
    onto the local AIJob row while the pipeline runs.

    Progress is capped at 95 while Modal is still working so the bar never shows
    100% before the final GLB has actually been uploaded to our storage.
    """

    def _write(payload: dict) -> None:
        prog = payload.get("progress")
        stage = payload.get("stage")
        msg = payload.get("message")

        changed = False

        new_prog: int | None = None
        if isinstance(prog, (int, float)):
            new_prog = int(prog)
        elif stage is not None and str(stage).lower() in _STAGE_PROGRESS:
            new_prog = _STAGE_PROGRESS[str(stage).lower()]
        if new_prog is not None:
            new_prog = max(0, min(95, new_prog))
            # Never let the live bar move backwards.
            if new_prog > (job.progress or 0):
                job.progress = new_prog
                changed = True

        if stage is not None:
            stage_str = str(stage)[:64]
            if stage_str != (job.stage or ""):
                job.stage = stage_str
                changed = True

        if msg is not None:
            msg_str = str(msg)
            if msg_str != (job.message or ""):
                job.message = msg_str
                changed = True

        if changed:
            job.updated_at = dt.datetime.now(dt.timezone.utc)
            try:
                db.commit()
            except Exception:
                db.rollback()

    return _write


def _as_bool(value: Any, default: bool = True) -> bool:
    if value is None:
        return default

    if isinstance(value, bool):
        return value

    if isinstance(value, int):
        return value != 0

    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "on", "texture", "with_texture"}

    return default


@celery_app.task(name="app.workers.tasks.ai_generate_task")
def ai_generate_task(job_id: str):
    db = _db()
    job = db.get(AIJob, job_id)

    if not job:
        db.close()
        return

    try:
        job.status = "running"
        job.progress = 5
        job.stage = "starting"
        job.message = "Preparing AI pipeline..."
        job.error = None
        db.commit()

        # Live progress sink: mirrors Modal's progress/stage/message onto the
        # job row on every poll so the AI page can render a real-time bar.
        on_progress = _make_progress_writer(job, db)

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)

            # Modal returns a finished GLB, so this is the final output (no
            # local repair step is applied to AI output).
            glb_final = td_path / "model.glb"

            settings_json = job.settings_json or {}

            with_texture = _as_bool(
                settings_json.get("with_texture", settings_json.get("texture")),
                default=True,
            )

            image_base64 = settings_json.get("image_base64")
            image_filename = settings_json.get("image_filename") or "upload.png"
            image_mime = settings_json.get("image_mime")
            voice_text = (settings_json.get("voice_text") or "").strip()

            if image_base64:
                img_path = td_path / image_filename
                img_path.write_bytes(base64.b64decode(image_base64))

                result = image_to_3d(
                    img_path, glb_final, with_texture=with_texture, on_progress=on_progress
                )

                if not image_mime:
                    image_mime, _ = mimetypes.guess_type(img_path.name)
                image_mime = image_mime or "image/png"

                out_key_img = f"{job.user_id}/{job.id}/outputs/{img_path.name}"
                s3.upload_file(
                    str(img_path),
                    settings.s3_bucket_job_outputs,
                    out_key_img,
                    content_type=image_mime,
                )
                job.output_image_key = out_key_img
                job.preview_keys = [out_key_img]

            elif voice_text:
                result = voice_to_3d(
                    voice_text, glb_final, with_texture=with_texture, on_progress=on_progress
                )
                job.preview_keys = []

            elif settings_json.get("voice_base64"):
                # The deployed Modal app accepts a transcript, not raw audio.
                raise ValueError(
                    "Voice input requires a transcript. Provide settings.voice_text; "
                    "raw audio is not supported by the configured AI endpoint."
                )

            else:
                if not job.prompt:
                    raise ValueError("Missing prompt, image_base64, or voice_text")

                result = prompt_to_3d(
                    job.prompt, glb_final, with_texture=with_texture, on_progress=on_progress
                )
                job.preview_keys = []

            # Modal finished and the GLB is downloaded locally; now persist it.
            job.stage = "finalizing"
            job.message = "Finalizing 3D model..."
            job.progress = max(job.progress or 0, 96)
            db.commit()

            out_key_glb = f"{job.user_id}/{job.id}/outputs/model.glb"
            s3.upload_file(
                str(glb_final),
                settings.s3_bucket_job_outputs,
                out_key_glb,
                content_type="model/gltf-binary",
            )
            job.output_glb_key = out_key_glb

            if not job.preview_keys:
                job.preview_keys = [out_key_glb]

            # Record honest texture status + Modal artifact URLs from the
            # actual output so the app can surface them.
            meta = dict(job.job_metadata or {})
            meta.update(
                {
                    "requested_texture": with_texture,
                    "with_texture": with_texture,
                    "textured": result.textured,
                    "final_kind": result.final_kind,
                    "fallback_used": result.fallback_used,
                    "selected_glb": result.selected_glb,
                    "texture_files": result.texture_files,
                    "raw_glb_url": result.raw_glb_url,
                    "condition_image_url": result.condition_image_url,
                    "texture_png_url": result.texture_png_url,
                    "texture_debug_url": result.texture_debug_url,
                    "artifacts": result.artifacts,
                }
            )
            job.job_metadata = meta

            job.status = "succeeded"
            job.progress = 100
            job.stage = "done"
            job.message = "3D model ready"
            job.updated_at = dt.datetime.now(dt.timezone.utc)
            db.commit()
            notify.notify_ai_job_completed(None, job.user_id, job.id)

    except Exception as e:
        _mark_failed(job, str(e), db)

    finally:
        db.close()


@celery_app.task(name="app.workers.tasks.scan_reconstruct_task")
def scan_reconstruct_task(job_id: str):
    db = _db()
    job = db.get(ScanJob, job_id)

    if not job:
        db.close()
        return

    try:
        job.status = "running"
        job.progress = 5
        job.error = None
        db.commit()

        input_keys = list(job.input_keys or [])
        if not input_keys:
            raise ValueError("No input images were uploaded for this scan job")

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)

            inputs = td_path / "inputs"
            inputs.mkdir(parents=True, exist_ok=True)

            out_glb = td_path / "scan.glb"
            out_fixed = td_path / "scan_fixed.glb"

            # Download every uploaded image from storage into the local input
            # folder BEFORE reconstruction runs.
            for key in input_keys:
                local = inputs / Path(key).name
                s3.download_file(settings.s3_bucket_scans_raw, key, str(local))

            job.progress = 30
            db.commit()

            # Real reconstruction (raises a clear error if no engine is
            # configured on this worker — never writes a fake placeholder).
            reconstruct_from_images(inputs, out_glb)

            job.progress = 70
            db.commit()

            repair_mesh(out_glb, out_fixed)

            job.progress = 85
            db.commit()

            out_key_glb = f"{job.user_id}/{job.id}/outputs/scan.glb"
            s3.upload_file(
                str(out_fixed),
                settings.s3_bucket_job_outputs,
                out_key_glb,
                content_type="model/gltf-binary",
            )

            job.output_glb_key = out_key_glb
            job.preview_keys = [out_key_glb]
            job.status = "succeeded"
            job.progress = 100
            job.updated_at = dt.datetime.now(dt.timezone.utc)
            db.commit()
            notify.notify_scan_completed(None, job.user_id, job.id)

    except Exception as e:
        _mark_failed(job, str(e), db)

    finally:
        db.close()