from __future__ import annotations

import mimetypes
import datetime as dt
import uuid
from pathlib import Path
from typing import Iterator

import httpx
from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.api.schemas.marketplace import AssetOut
from app.api.schemas.photogrammetry import (
    PhotogrammetryAssetCreateIn,
    PhotogrammetryJobCreatedOut,
    PhotogrammetryJobOutputOut,
    PhotogrammetryJobStatusOut,
)
from app.core.errors import bad_request, not_found, unauthorized
from app.core.config import settings
from app.core.security import decode_token
from app.db.models.marketplace import Asset
from app.db.models.user import User, UserProfile
from app.services.photogrammetry_jobs import (
    OUTPUT_CONTENT_TYPES,
    PhotogrammetryJob,
    photogrammetry_jobs,
)
from app.services import photogrammetry_modal as modal_pg
from app.services.s3 import s3

router = APIRouter()
_bearer = HTTPBearer(auto_error=False)

# NOTE: The photogrammetry pipeline now runs on the deployed Modal app. This
# backend is a proxy/controller: it forwards reconstruction jobs to Modal, caches
# the returned outputs per-job, and exposes them through the stable routes below.
# Jobs are user-owned; every endpoint requires authentication and rejects access
# to another user's job. Download URLs additionally carry a short-lived signed
# token so the headerless GLB preview / file downloads can authorize without a
# bearer header.


@router.post("/jobs", response_model=PhotogrammetryJobCreatedOut, status_code=202)
async def create_job(
    files: list[UploadFile] = File(...),
    texture_mode: str | None = Form(None),
    no_strict_mask: bool | None = Form(None),
    user=Depends(get_current_user),
):
    if not files:
        bad_request("Upload at least one image")
    try:
        job = photogrammetry_jobs.create_job(
            files,
            user_id=str(user.id),
            texture_mode=texture_mode,
            no_strict_mask=no_strict_mask,
        )
    except ValueError as exc:
        bad_request(str(exc))
    return {
        "job_id": job.job_id,
        "status": job.status,
        "progress": job.progress,
    }


@router.get("/jobs/{job_id}/status", response_model=PhotogrammetryJobStatusOut)
async def get_job_status(job_id: str, user=Depends(get_current_user)):
    job = photogrammetry_jobs.get_for_user(job_id, str(user.id))
    if not job:
        not_found("Photogrammetry job not found")
    return job.to_status()


@router.get("/jobs", response_model=list[PhotogrammetryJobStatusOut])
async def list_jobs(limit: int = 20, user=Depends(get_current_user)):
    return photogrammetry_jobs.list_jobs(user_id=str(user.id), limit=limit)


@router.get("/jobs/{job_id}/output", response_model=PhotogrammetryJobOutputOut)
async def get_job_output(job_id: str, user=Depends(get_current_user)):
    job = photogrammetry_jobs.get_for_user(job_id, str(user.id))
    if not job:
        not_found("Photogrammetry job not found")
    if job.status != "completed":
        bad_request("Photogrammetry job has not completed yet")
    return {
        "job_id": job.job_id,
        "status": job.status,
        "files": photogrammetry_jobs.list_output_files(job),
    }


def _authorize_download(
    job_id: str,
    token: str | None,
    creds: HTTPAuthorizationCredentials | None,
    db: Session,
) -> PhotogrammetryJob:
    """Authorize a file download via the signed URL token OR a bearer header.

    The signed token is the primary path (it lets the headerless ModelViewer and
    plain download client fetch files); a valid owner bearer token is also
    accepted. Either way the returned job is guaranteed to belong to the caller.
    """
    # 1) Signed download token in the query string.
    if token:
        owner_id = photogrammetry_jobs.verify_download_token(job_id, token)
        if owner_id:
            job = photogrammetry_jobs.get_for_user(job_id, owner_id)
            if job:
                return job

    # 2) Fall back to a bearer access token for the owning user.
    if creds and creds.credentials:
        try:
            payload = decode_token(creds.credentials)
        except Exception:
            payload = None
        if payload and payload.get("type") == "access":
            user_id = payload.get("sub")
            user = db.get(User, user_id) if user_id else None
            if user and user.is_active:
                job = photogrammetry_jobs.get_for_user(job_id, str(user.id))
                if job:
                    return job

    unauthorized("Not authorized for this photogrammetry file")


def _stream_local_file(path: Path, chunk_size: int = 1024 * 1024) -> Iterator[bytes]:
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            yield chunk


def _proxy_remote_file(url: str) -> StreamingResponse:
    """Stream a file straight from Modal (used only if the contract ever exposes
    per-file URLs; the current ZIP contract caches locally instead)."""
    client = httpx.Client(timeout=httpx.Timeout(settings.photogrammetry_modal_timeout_s), follow_redirects=True)
    upstream = client.stream("GET", url)
    response = upstream.__enter__()
    response.raise_for_status()

    def _iter() -> Iterator[bytes]:
        try:
            for chunk in response.iter_bytes():
                yield chunk
        finally:
            upstream.__exit__(None, None, None)
            client.close()

    media_type = response.headers.get("content-type", "application/octet-stream")
    return StreamingResponse(_iter(), media_type=media_type)


@router.get("/jobs/{job_id}/download/{filename:path}")
async def download_output_file(
    job_id: str,
    filename: str,
    token: str | None = Query(None),
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
):
    job = _authorize_download(job_id, token, creds, db)
    try:
        path = photogrammetry_jobs.resolve_output_file(job, filename)
    except FileNotFoundError:
        not_found("Requested output file was not found")

    media_type = OUTPUT_CONTENT_TYPES.get(path.suffix.lower())
    if media_type is None:
        media_type, _ = mimetypes.guess_type(path.name)
    media_type = media_type or "application/octet-stream"

    # Stream from the local cache so large GLB downloads never buffer fully in
    # memory. Content-Length lets clients show progress and verify completeness.
    headers = {
        "Content-Length": str(path.stat().st_size),
        "Content-Disposition": f'inline; filename="{path.name}"',
    }
    return StreamingResponse(_stream_local_file(path), media_type=media_type, headers=headers)


@router.post("/jobs/{job_id}/asset", response_model=AssetOut)
async def create_asset_from_job(
    job_id: str,
    payload: PhotogrammetryAssetCreateIn,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    job = photogrammetry_jobs.get_for_user(job_id, str(user.id))
    if not job:
        not_found("Photogrammetry job not found")
    if job.status != "completed":
        bad_request("Photogrammetry job has not completed yet")

    output_files = [path for path in job.output_dir.rglob("*") if path.is_file()]
    model_file = modal_pg.find_primary_model(job.output_dir)
    if model_file is None:
        bad_request("No model output file was found for this job")

    # Download the final model from the local Modal cache, upload every output to
    # the marketplace models bucket, and keep the primary model's object key.
    uploaded_keys: list[str] = []
    model_key: str | None = None
    for path in output_files:
        relative = path.relative_to(job.output_dir).as_posix()
        key = f"{user.id}/photogrammetry/{job_id}/{uuid.uuid4()}_{relative}"
        content_type = OUTPUT_CONTENT_TYPES.get(path.suffix.lower())
        if content_type is None:
            content_type, _ = mimetypes.guess_type(path.name)
        s3.upload_file(
            str(path),
            settings.s3_bucket_marketplace_models,
            key,
            content_type=content_type or "application/octet-stream",
        )
        uploaded_keys.append(key)
        if path == model_file:
            model_key = key
    if model_key is None:
        bad_request("Could not save the primary model output for this job")

    asset = Asset(
        creator_id=user.id,
        title=payload.title,
        description=payload.description,
        tags=payload.tags,
        category=payload.category,
        style=payload.style,
        is_paid=payload.is_paid,
        price=payload.price,
        currency=payload.currency,
        visibility="published" if payload.publish else "draft",
        published_at=dt.datetime.now(dt.timezone.utc) if payload.publish else None,
        model_object_key=model_key,
        thumb_object_key=payload.thumb_object_key,
        preview_object_keys=[model_key],
        meta_json={
            "source": "photogrammetry",
            "photogrammetry_job_id": job_id,
            "photogrammetry_modal_run_id": job.modal_run_id,
            "output_files": uploaded_keys,
            "likes": 0,
        },
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    profile = db.query(UserProfile).filter(UserProfile.user_id == user.id).one_or_none()
    creator_username = profile.username if profile else None
    meta = dict(asset.meta_json or {})
    if creator_username:
        meta["creator_username"] = creator_username
    return AssetOut(
        id=str(asset.id),
        title=asset.title,
        description=asset.description,
        tags=asset.tags or [],
        category=asset.category,
        style=asset.style,
        creator_id=str(asset.creator_id),
        is_paid=asset.is_paid,
        price=asset.price,
        currency=asset.currency,
        visibility=asset.visibility,
        published_at=asset.published_at.isoformat() if asset.published_at else None,
        thumb_object_key=asset.thumb_object_key,
        thumb_url=s3.presign_get(settings.s3_bucket_marketplace_thumbs, asset.thumb_object_key, expires=900) if asset.thumb_object_key else None,
        model_object_key=asset.model_object_key,
        preview_url=s3.presign_get(settings.s3_bucket_marketplace_models, asset.model_object_key, expires=900),
        metadata=meta,
    )
