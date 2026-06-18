"""Photogrammetry job store — Modal proxy/controller.

The backend no longer runs a local COLMAP/OpenMVS pipeline. Instead it:

  1. Accepts uploaded images (or a ZIP of images) over the stable HTTP API.
  2. Forwards them to the deployed Modal photogrammetry app (``POST /reconstruct``).
  3. Extracts the returned ZIP of outputs into a per-job local cache.
  4. Serves those cached outputs back through the unchanged download routes.

Jobs are owned by the user that created them; the store records ``user_id`` and
persists a small ``meta.json`` next to the cached outputs so ownership and
status survive an API restart. Per-file access is authorized either by the
owning bearer user or by the signed token embedded in the download URLs (so the
headerless GLB preview / file downloads can authorize without a header).
"""

from __future__ import annotations

import hashlib
import hmac
import json
import mimetypes
import shutil
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZipFile

from fastapi import UploadFile

from app.core.config import settings
from app.services import photogrammetry_modal as modal_pg

ALLOWED_SUFFIXES = modal_pg.IMAGE_SUFFIXES
ALLOWED_ARCHIVE_SUFFIXES = {".zip"}
OUTPUT_CONTENT_TYPES = {
    ".glb": "model/gltf-binary",
    ".gltf": "model/gltf+json",
    ".obj": "model/obj",
    ".ply": "application/octet-stream",
    ".mtl": "text/plain",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".html": "text/html",
    ".json": "application/json",
    ".md": "text/markdown",
}

# Coarse progress for the blocking Modal call (no intermediate signal exists).
_PROGRESS_UPLOADING = 10
_PROGRESS_RUNNING = 55


def _resolve_jobs_root() -> Path:
    raw = Path(settings.photogrammetry_jobs_root)
    if raw.is_absolute():
        root = raw
    else:
        # Resolve relative to the backend package root (…/backend).
        backend_root = Path(__file__).resolve().parents[2]
        root = backend_root / raw
    root.mkdir(parents=True, exist_ok=True)
    return root.resolve()


JOBS_ROOT = _resolve_jobs_root()


class _Unset:
    pass


_UNSET = _Unset()


@dataclass
class PhotogrammetryJob:
    job_id: str
    user_id: str
    status: str
    progress: int
    created_at: str
    updated_at: str
    output_dir: Path
    texture_mode: str = ""
    no_strict_mask: bool = False
    modal_run_id: str | None = None
    error: str | None = None
    files: list[str] = field(default_factory=list)

    def to_status(self) -> dict[str, object]:
        return {
            "job_id": self.job_id,
            "status": self.status,
            "progress": self.progress,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "error": self.error,
        }


class PhotogrammetryJobStore:
    def __init__(self) -> None:
        self._jobs: dict[str, PhotogrammetryJob] = {}
        self._lock = threading.Lock()
        JOBS_ROOT.mkdir(parents=True, exist_ok=True)
        self._load_existing_jobs()

    # --------------------------------------------------------------------- #
    # Creation
    # --------------------------------------------------------------------- #
    def create_job(
        self,
        uploads: list[UploadFile],
        *,
        user_id: str,
        texture_mode: str | None = None,
        no_strict_mask: bool | None = None,
    ) -> PhotogrammetryJob:
        texture_mode = (texture_mode or settings.photogrammetry_texture_mode or "vertexcolor").strip()
        if no_strict_mask is None:
            no_strict_mask = settings.photogrammetry_no_strict_mask

        job_id = uuid.uuid4().hex
        job_root = JOBS_ROOT / job_id
        input_dir = job_root / "input"
        output_dir = job_root / "output"
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        saved_names = self._persist_uploads(uploads, input_dir)
        if not saved_names:
            shutil.rmtree(job_root, ignore_errors=True)
            raise ValueError("Upload at least one supported image or a ZIP containing images")

        now = _now_iso()
        job = PhotogrammetryJob(
            job_id=job_id,
            user_id=str(user_id),
            status="pending",
            progress=0,
            created_at=now,
            updated_at=now,
            output_dir=output_dir,
            texture_mode=texture_mode,
            no_strict_mask=bool(no_strict_mask),
            files=saved_names,
        )
        with self._lock:
            self._jobs[job_id] = job
        self._write_meta(job)
        threading.Thread(target=self._run_modal, args=(job_id,), daemon=True).start()
        return job

    def _persist_uploads(self, uploads: list[UploadFile], input_dir: Path) -> list[str]:
        """Validate (type + size + count) and save uploads to ``input_dir``.

        ZIP uploads are expanded into their contained images.
        """
        saved: list[str] = []
        max_images = max(1, settings.photogrammetry_max_images)
        max_bytes = settings.photogrammetry_max_image_bytes

        for index, upload in enumerate(uploads, start=1):
            filename = Path(upload.filename or f"image_{index}.jpg").name
            suffix = Path(filename).suffix.lower()

            if suffix in ALLOWED_ARCHIVE_SUFFIXES:
                archive_path = input_dir / f"_upload_{index}.zip"
                self._write_upload(archive_path, upload, max_bytes=settings.max_upload_bytes)
                try:
                    saved.extend(
                        self._extract_zip_images(archive_path, input_dir, max_bytes=max_bytes)
                    )
                finally:
                    archive_path.unlink(missing_ok=True)
                continue

            if suffix not in ALLOWED_SUFFIXES:
                raise ValueError(
                    f"Unsupported file type for '{filename}'. Allowed: "
                    f"{', '.join(sorted(ALLOWED_SUFFIXES))} or a .zip of images"
                )

            target = input_dir / filename
            counter = 1
            while target.exists():
                target = input_dir / f"{counter}_{filename}"
                counter += 1
            self._write_upload(target, upload, max_bytes=max_bytes)
            saved.append(target.name)

            if len(saved) > max_images:
                raise ValueError(f"Too many images; the maximum is {max_images}")

        if len(saved) > max_images:
            raise ValueError(f"Too many images; the maximum is {max_images}")
        return saved

    # --------------------------------------------------------------------- #
    # Modal execution (background thread)
    # --------------------------------------------------------------------- #
    def _run_modal(self, job_id: str) -> None:
        job = self.get(job_id)
        if not job:
            return
        input_dir = JOBS_ROOT / job_id / "input"
        image_paths = sorted(
            p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() in ALLOWED_SUFFIXES
        )
        if len(image_paths) < settings.photogrammetry_min_images:
            self._update(
                job_id,
                status="failed",
                progress=0,
                error=(
                    f"Need at least {settings.photogrammetry_min_images} images to reconstruct; "
                    f"got {len(image_paths)}"
                ),
            )
            return

        self._update(job_id, status="processing", progress=_PROGRESS_UPLOADING, error=None)
        try:
            self._update(job_id, progress=_PROGRESS_RUNNING)
            zip_bytes, run_id = modal_pg.reconstruct(
                image_paths,
                texture_mode=job.texture_mode,
                no_strict_mask=job.no_strict_mask,
                timeout_s=settings.photogrammetry_modal_timeout_s,
            )
            output_dir = job.output_dir
            # Replace any previous cache before extracting fresh outputs.
            if output_dir.exists():
                shutil.rmtree(output_dir, ignore_errors=True)
            output_dir.mkdir(parents=True, exist_ok=True)
            modal_pg.extract_zip(zip_bytes, output_dir)

            if modal_pg.find_primary_model(output_dir) is None:
                self._update(
                    job_id,
                    status="failed",
                    progress=0,
                    error="Reconstruction finished but no GLB/OBJ/PLY model was produced",
                )
                return

            with self._lock:
                cur = self._jobs.get(job_id)
                if cur:
                    cur.modal_run_id = run_id
            self._update(job_id, status="completed", progress=100, error=None)
        except modal_pg.PhotogrammetryModalError as exc:
            self._update(job_id, status="failed", progress=0, error=str(exc))
        except Exception as exc:  # pragma: no cover - defensive
            self._update(job_id, status="failed", progress=0, error=str(exc))

    # --------------------------------------------------------------------- #
    # Reads
    # --------------------------------------------------------------------- #
    def get(self, job_id: str) -> PhotogrammetryJob | None:
        with self._lock:
            job = self._jobs.get(job_id)
        if job:
            return job
        return self._load_job_from_disk(job_id)

    def get_for_user(self, job_id: str, user_id: str) -> PhotogrammetryJob | None:
        """Return the job only if it belongs to ``user_id`` (else None)."""
        job = self.get(job_id)
        if job and job.user_id == str(user_id):
            return job
        return None

    def list_jobs(self, *, user_id: str, limit: int = 20) -> list[dict[str, object]]:
        self._load_existing_jobs()
        with self._lock:
            jobs = [j for j in self._jobs.values() if j.user_id == str(user_id)]
        jobs.sort(key=lambda job: job.updated_at, reverse=True)
        return [job.to_status() for job in jobs[: max(1, min(limit, 100))]]

    def list_output_files(self, job: PhotogrammetryJob) -> list[dict[str, object]]:
        token = self.make_download_token(job.job_id, job.user_id)
        files: list[dict[str, object]] = []
        for path in sorted(p for p in job.output_dir.rglob("*") if p.is_file()):
            relative = path.relative_to(job.output_dir).as_posix()
            suffix = path.suffix.lower()
            content_type = OUTPUT_CONTENT_TYPES.get(suffix)
            if content_type is None:
                content_type, _ = mimetypes.guess_type(path.name)
            files.append(
                {
                    "filename": relative,
                    "file_size": path.stat().st_size,
                    "file_type": suffix.lstrip(".") or "file",
                    "content_type": content_type or "application/octet-stream",
                    "download_url": (
                        f"/api/photogrammetry/jobs/{job.job_id}/download/{relative}?token={token}"
                    ),
                }
            )
        return files

    def resolve_output_file(self, job: PhotogrammetryJob, filename: str) -> Path:
        output_root = job.output_dir.resolve()
        target = (job.output_dir / filename).resolve()
        if target == output_root or output_root not in target.parents or not target.is_file():
            raise FileNotFoundError(filename)
        return target

    # --------------------------------------------------------------------- #
    # Signed download tokens (HMAC over job_id + user_id + expiry)
    # --------------------------------------------------------------------- #
    def make_download_token(self, job_id: str, user_id: str) -> str:
        exp = int(time.time()) + max(60, settings.photogrammetry_download_token_expires_s)
        sig = self._sign(job_id, str(user_id), exp)
        return f"{user_id}.{exp}.{sig}"

    def verify_download_token(self, job_id: str, token: str) -> str | None:
        """Return the authorized ``user_id`` if the token is valid for ``job_id``."""
        if not token:
            return None
        try:
            user_id, exp_raw, sig = token.rsplit(".", 2)
            exp = int(exp_raw)
        except (ValueError, AttributeError):
            return None
        if exp < int(time.time()):
            return None
        expected = self._sign(job_id, user_id, exp)
        if not hmac.compare_digest(expected, sig):
            return None
        return user_id

    @staticmethod
    def _sign(job_id: str, user_id: str, exp: int) -> str:
        msg = f"{job_id}:{user_id}:{exp}".encode("utf-8")
        return hmac.new(settings.jwt_secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()

    # --------------------------------------------------------------------- #
    # State persistence
    # --------------------------------------------------------------------- #
    def _update(
        self,
        job_id: str,
        *,
        status: str | None = None,
        progress: int | None = None,
        error: str | None | object = _UNSET,
    ) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return
            if status is not None:
                job.status = status
            if progress is not None:
                job.progress = progress
            if error is not _UNSET:
                job.error = error if isinstance(error, str) or error is None else str(error)
            job.updated_at = _now_iso()
            snapshot = job
        self._write_meta(snapshot)

    def _meta_path(self, job_id: str) -> Path:
        return JOBS_ROOT / job_id / "meta.json"

    def _write_meta(self, job: PhotogrammetryJob) -> None:
        meta = {
            "job_id": job.job_id,
            "user_id": job.user_id,
            "status": job.status,
            "progress": job.progress,
            "created_at": job.created_at,
            "updated_at": job.updated_at,
            "texture_mode": job.texture_mode,
            "no_strict_mask": job.no_strict_mask,
            "modal_run_id": job.modal_run_id,
            "error": job.error,
            "files": job.files,
        }
        try:
            path = self._meta_path(job.job_id)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(meta), encoding="utf-8")
        except Exception:
            # Persistence is best-effort; the in-memory record is authoritative.
            pass

    def _load_existing_jobs(self) -> None:
        if not JOBS_ROOT.exists():
            return
        for job_root in JOBS_ROOT.iterdir():
            if not job_root.is_dir():
                continue
            with self._lock:
                if job_root.name in self._jobs:
                    continue
            self._load_job_from_disk(job_root.name)

    def _load_job_from_disk(self, job_id: str) -> PhotogrammetryJob | None:
        job_root = JOBS_ROOT / job_id
        meta_path = job_root / "meta.json"
        if not meta_path.is_file():
            return None
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            return None
        output_dir = job_root / "output"
        job = PhotogrammetryJob(
            job_id=meta.get("job_id", job_id),
            user_id=str(meta.get("user_id", "")),
            status=str(meta.get("status", "pending")),
            progress=int(meta.get("progress", 0) or 0),
            created_at=str(meta.get("created_at", _now_iso())),
            updated_at=str(meta.get("updated_at", _now_iso())),
            output_dir=output_dir,
            texture_mode=str(meta.get("texture_mode", "")),
            no_strict_mask=bool(meta.get("no_strict_mask", False)),
            modal_run_id=meta.get("modal_run_id"),
            error=meta.get("error"),
            files=list(meta.get("files", []) or []),
        )
        with self._lock:
            self._jobs[job_id] = job
        return job

    # --------------------------------------------------------------------- #
    # Upload helpers
    # --------------------------------------------------------------------- #
    @staticmethod
    def _write_upload(target: Path, upload: UploadFile, *, max_bytes: int) -> None:
        source = upload.file
        source.seek(0)
        written = 0
        chunk_size = 1024 * 1024
        with target.open("wb") as handle:
            while True:
                chunk = source.read(chunk_size)
                if not chunk:
                    break
                written += len(chunk)
                if max_bytes and written > max_bytes:
                    handle.close()
                    target.unlink(missing_ok=True)
                    raise ValueError(
                        f"'{upload.filename or target.name}' exceeds the maximum allowed size "
                        f"({max_bytes} bytes)"
                    )
                handle.write(chunk)
        source.seek(0)

    @staticmethod
    def _extract_zip_images(archive_path: Path, input_dir: Path, *, max_bytes: int) -> list[str]:
        saved: list[str] = []
        with ZipFile(archive_path) as archive:
            for member in archive.infolist():
                if member.is_dir():
                    continue
                name = Path(member.filename).name
                if not name:
                    continue
                suffix = Path(name).suffix.lower()
                if suffix not in ALLOWED_SUFFIXES:
                    continue
                if max_bytes and member.file_size > max_bytes:
                    raise ValueError(
                        f"'{name}' inside the ZIP exceeds the maximum allowed size "
                        f"({max_bytes} bytes)"
                    )
                target = input_dir / name
                counter = 1
                while target.exists():
                    target = input_dir / f"{counter}_{name}"
                    counter += 1
                with archive.open(member) as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                saved.append(target.name)
        return saved


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


photogrammetry_jobs = PhotogrammetryJobStore()
