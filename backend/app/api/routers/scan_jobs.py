from __future__ import annotations
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select, desc
from app.api.deps import get_db, get_current_user
from app.api.schemas.common import PresignedURL, PresignIn
from app.api.schemas.jobs import ScanJobCreateIn, JobOut, DownloadOut
from app.core.errors import not_found, forbidden, bad_request
from app.db.models.jobs import ScanJob
from app.workers.tasks import scan_reconstruct_task
from app.services.s3 import s3
from app.core.config import settings

router = APIRouter()

def to_job_out(j: ScanJob) -> JobOut:
    return JobOut(
        id=str(j.id), status=j.status, progress=j.progress,
        created_at=j.created_at.isoformat(), updated_at=j.updated_at.isoformat() if j.updated_at else None,
        prompt=None,
        metadata=j.job_metadata or {}, output_glb_key=j.output_glb_key, output_stl_key=j.output_stl_key,
        preview_keys=j.preview_keys or [], error=j.error
    )

@router.post("/jobs", response_model=JobOut)
def create_scan_job(payload: ScanJobCreateIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    if payload.kind not in ["photos", "zip"]:
        bad_request("kind must be photos|zip")
    job = ScanJob(user_id=user.id, status="created", progress=0, job_metadata={"kind": payload.kind})
    db.add(job); db.commit(); db.refresh(job)
    return to_job_out(job)

@router.post("/jobs/{job_id}/presign", response_model=PresignedURL)
def presign_upload(job_id: str, payload: PresignIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    j = db.get(ScanJob, job_id)
    if not j: not_found()
    if j.user_id != user.id: forbidden()
    key = f"{user.id}/{job_id}/inputs/{uuid.uuid4()}_{payload.filename}"
    url = s3.presign_put(
        settings.s3_bucket_scans_raw,
        key,
        expires=3600,
        content_type=payload.content_type,
    )
    # store key in job
    keys = list(j.input_keys or [])
    keys.append(key)
    j.input_keys = keys
    db.commit()
    return PresignedURL(url=url, headers={"Content-Type": payload.content_type})

@router.post("/jobs/{job_id}/start", response_model=JobOut)
def start_reconstruction(job_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    j = db.get(ScanJob, job_id)
    if not j: not_found()
    if j.user_id != user.id: forbidden()
    if not j.input_keys:
        bad_request("Upload images first")
    j.status = "queued"
    j.progress = 0
    db.commit()
    scan_reconstruct_task.delay(str(j.id))
    return to_job_out(j)

@router.get("/jobs", response_model=list[JobOut])
def list_jobs(limit: int = 20, offset: int = 0, db: Session = Depends(get_db), user = Depends(get_current_user)):
    q = select(ScanJob).where(ScanJob.user_id == user.id).order_by(desc(ScanJob.created_at)).limit(limit).offset(offset)
    items = db.execute(q).scalars().all()
    return [to_job_out(j) for j in items]

@router.get("/jobs/{job_id}/download/glb", response_model=DownloadOut)
def download_glb(job_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    j = db.get(ScanJob, job_id)
    if not j: not_found()
    if j.user_id != user.id: forbidden()
    if not j.output_glb_key: not_found("No GLB yet")
    url = s3.presign_get(settings.s3_bucket_job_outputs, j.output_glb_key, expires=900)
    return DownloadOut(url=url, expires_in=900)
