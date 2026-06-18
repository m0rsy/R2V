from __future__ import annotations
import uuid
import datetime as dt
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select, desc
from app.api.deps import get_db, get_current_user
from app.api.schemas.jobs import AIJobCreateIn, JobOut, DownloadOut, AIJobAssetCreateIn
from app.api.schemas.marketplace import AssetOut
from app.core.errors import not_found, forbidden, bad_request
from app.db.models.jobs import AIJob
from app.db.models.marketplace import Asset
from app.db.models.user import UserProfile
from app.workers.tasks import ai_generate_task
from app.services.s3 import s3
from app.core.config import settings

router = APIRouter()
legacy_router = APIRouter()

def to_job_out(j: AIJob) -> JobOut:
    meta = j.job_metadata or {}
    settings_json = j.settings_json or {}

    # Presign the final GLB once it exists so the app can view/download it
    # directly from the poll response (model_url/glb_url/download_url all point
    # at the same object for frontend convenience / backward compatibility).
    model_url: str | None = None
    if j.output_glb_key:
        try:
            model_url = s3.presign_get(
                settings.s3_bucket_job_outputs, j.output_glb_key, expires=3600
            )
        except Exception:
            model_url = None

    # Re-presign the stored input/preview image so the AI chat can restore an
    # uploaded image after a reload (the originally stored URL has expired).
    output_image_url: str | None = None
    if j.output_image_key:
        try:
            output_image_url = s3.presign_get(
                settings.s3_bucket_job_outputs, j.output_image_key, expires=3600
            )
        except Exception:
            output_image_url = None

    artifacts = meta.get("artifacts") if isinstance(meta.get("artifacts"), dict) else {}

    return JobOut(
        id=str(j.id), status=j.status, progress=j.progress,
        stage=j.stage, message=j.message,
        created_at=j.created_at.isoformat(), updated_at=j.updated_at.isoformat() if j.updated_at else None,
        prompt=j.prompt,
        input_type=meta.get("input_type") or settings_json.get("input_type"),
        with_texture=meta.get("with_texture") if meta.get("with_texture") is not None else settings_json.get("with_texture"),
        textured=meta.get("textured"),
        metadata=meta, output_glb_key=j.output_glb_key, output_stl_key=j.output_stl_key,
        output_image_key=j.output_image_key, preview_keys=j.preview_keys or [],
        model_url=model_url, glb_url=model_url, download_url=model_url,
        output_image_url=output_image_url,
        raw_glb_url=meta.get("raw_glb_url"),
        condition_image_url=meta.get("condition_image_url"),
        texture_png_url=meta.get("texture_png_url"),
        texture_debug_url=meta.get("texture_debug_url"),
        artifacts=artifacts,
        error=j.error,
    )

def _create_job(payload: AIJobCreateIn, db: Session, user) -> JobOut:
    input_type = payload.input_type  # already validated/normalized by the schema
    prompt = (payload.prompt or "").strip()
    settings_json = dict(payload.settings or {})

    # Validate that the required input for the chosen generation type is present.
    if input_type == "prompt" and not prompt:
        bad_request("A text prompt is required for prompt generation.")
    if input_type == "image" and not settings_json.get("image_base64"):
        bad_request("An image file is required for image generation.")
    if input_type == "voice" and not settings_json.get("voice_base64"):
        bad_request("A voice file is required for voice generation.")

    with_texture = bool(payload.with_texture)
    settings_json["with_texture"] = with_texture
    settings_json["input_type"] = input_type

    # The DB column is NOT NULL, so keep a non-empty placeholder for non-prompt jobs.
    stored_prompt = prompt or f"[{input_type}]"

    job = AIJob(
        user_id=user.id,
        prompt=stored_prompt,
        settings_json=settings_json,
        job_metadata={"with_texture": with_texture, "input_type": input_type},
        status="queued",
        progress=0,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    ai_generate_task.delay(str(job.id))
    return to_job_out(job)

@router.post("/jobs", response_model=JobOut)
def create_job(payload: AIJobCreateIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    return _create_job(payload, db, user)

@legacy_router.post("/generate-from-text", response_model=JobOut)
def generate_from_text(payload: AIJobCreateIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    return _create_job(payload, db, user)

@router.get("/jobs", response_model=list[JobOut])
def list_jobs(limit: int = 20, offset: int = 0, db: Session = Depends(get_db), user = Depends(get_current_user)):
    q = select(AIJob).where(AIJob.user_id == user.id).order_by(desc(AIJob.created_at)).limit(limit).offset(offset)
    items = db.execute(q).scalars().all()
    return [to_job_out(j) for j in items]

@router.get("/jobs/{job_id}", response_model=JobOut)
def get_job(job_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    j = db.get(AIJob, job_id)
    if not j: not_found()
    if j.user_id != user.id: forbidden()
    return to_job_out(j)

@router.get("/jobs/{job_id}/download/glb", response_model=DownloadOut)
def download_glb(job_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    j = db.get(AIJob, job_id)
    if not j: not_found()
    if j.user_id != user.id: forbidden()
    if not j.output_glb_key: not_found("No GLB yet")
    url = s3.presign_get(settings.s3_bucket_job_outputs, j.output_glb_key, expires=900)
    return DownloadOut(url=url, expires_in=900)


def _asset_out(a: Asset, db: Session) -> AssetOut:
    """Build an AssetOut with presigned URLs only — never internal storage paths."""
    prof = db.execute(
        select(UserProfile).where(UserProfile.user_id == a.creator_id)
    ).scalar_one_or_none()
    meta = dict(a.meta_json or {})
    if prof and prof.username:
        meta.setdefault("creator_username", prof.username)
    meta.setdefault("likes", meta.get("likes", 0))
    thumb_url = (
        s3.presign_get(settings.s3_bucket_marketplace_thumbs, a.thumb_object_key, expires=900)
        if a.thumb_object_key
        else None
    )
    return AssetOut(
        id=str(a.id), title=a.title, description=a.description, tags=a.tags or [],
        category=a.category, style=a.style, creator_id=str(a.creator_id),
        is_paid=a.is_paid, price=a.price, currency=a.currency, visibility=a.visibility,
        published_at=a.published_at.isoformat() if a.published_at else None,
        thumb_object_key=a.thumb_object_key, thumb_url=thumb_url,
        model_object_key=a.model_object_key,
        preview_url=s3.presign_get(settings.s3_bucket_marketplace_models, a.model_object_key, expires=900),
        metadata=meta,
    )


@router.post("/jobs/{job_id}/asset", response_model=AssetOut)
def create_asset_from_job(
    job_id: str,
    payload: AIJobAssetCreateIn,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """Publish a succeeded AI job's generated GLB straight to the marketplace.

    Ownership is mandatory: only the user who generated the job may publish it.
    The GLB (and optional preview) are copied server-side from the private job
    bucket into the marketplace bucket; all object keys come from the trusted
    DB row, never from the request body.
    """
    j = db.get(AIJob, job_id)
    if not j:
        not_found("AI job not found")
    if j.user_id != user.id:
        forbidden()
    if j.status != "succeeded":
        bad_request("AI job has not succeeded yet")
    if not j.output_glb_key:
        bad_request("This job has no generated model to publish")

    # Idempotency: unless the user explicitly reposts, return the existing
    # marketplace listing already linked to this job instead of duplicating it.
    if not payload.repost:
        existing = db.execute(
            select(Asset)
            .where(Asset.creator_id == user.id)
            .where(Asset.meta_json["ai_job_id"].astext == str(job_id))
            .order_by(desc(Asset.created_at))
        ).scalars().first()
        if existing is not None:
            return _asset_out(existing, db)

    # Server-side copy of the GLB from the private job bucket into marketplace.
    model_key = f"{user.id}/ai/{job_id}/{uuid.uuid4().hex}_model.glb"
    s3.copy_object(
        settings.s3_bucket_job_outputs, j.output_glb_key,
        settings.s3_bucket_marketplace_models, model_key,
        content_type="model/gltf-binary",
    )

    # Thumbnail resolution, in priority order:
    #   1. A client-captured thumbnail already uploaded to the marketplace-thumbs
    #      bucket (key must live under THIS user's namespace).
    #   2. Otherwise, a server-side copy of the job's generated preview image.
    thumb_key: str | None = None
    if payload.thumb_object_key:
        # Guard: the presign flow always prefixes keys with "{user.id}/", so a
        # key outside that namespace would be someone else's object -> reject.
        if not payload.thumb_object_key.startswith(f"{user.id}/"):
            forbidden()
        thumb_key = payload.thumb_object_key
    elif payload.include_thumbnail and j.output_image_key:
        thumb_key = f"{user.id}/ai/{job_id}/{uuid.uuid4().hex}_thumb.png"
        try:
            s3.copy_object(
                settings.s3_bucket_job_outputs, j.output_image_key,
                settings.s3_bucket_marketplace_thumbs, thumb_key,
                content_type="image/png",
            )
        except Exception:
            # Thumbnail is best-effort; never block the listing on it.
            thumb_key = None

    publish = payload.publish
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
        visibility="published" if publish else "draft",
        published_at=dt.datetime.now(dt.timezone.utc) if publish else None,
        model_object_key=model_key,
        thumb_object_key=thumb_key,
        preview_object_keys=[model_key],
        meta_json={
            "source": "ai",
            "ai_job_id": str(job_id),
            "with_texture": (j.job_metadata or {}).get("with_texture"),
            "likes": 0,
        },
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return _asset_out(asset, db)
