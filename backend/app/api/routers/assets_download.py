from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_db, get_current_user
from app.api.schemas.jobs import DownloadOut
from app.core.errors import not_found, forbidden, bad_request
from app.db.models.marketplace import Asset, Download
from app.db.models.user import UserProfile
from app.services.entitlements import is_entitled_to_asset
from app.services import notifications as notify
from app.services.s3 import s3
from app.core.config import settings
from sqlalchemy import select

router = APIRouter()

def _actor_name(db: Session, user_id) -> str | None:
    """Best-effort display name for notification copy; never raises."""
    try:
        prof = db.execute(select(UserProfile).where(UserProfile.user_id == user_id)).scalar_one_or_none()
        return prof.username if prof and prof.username else None
    except Exception:
        return None

def _normalize_format(raw: str | None) -> str | None:
    if not raw:
        return None
    cleaned = raw.strip().lower()
    if not cleaned:
        return None
    if not cleaned.startswith("."):
        cleaned = f".{cleaned}"
    return cleaned

def _extension_from_key(key: str) -> str | None:
    if "." not in key:
        return None
    return f".{key.rsplit('.', 1)[-1].lower()}"

@router.get("/assets/{asset_id}/download", response_model=DownloadOut)
def download_asset(
    asset_id: str,
    format: str | None = None,
    db: Session = Depends(get_db),
    user = Depends(get_current_user),
):
    a = db.get(Asset, asset_id)
    if not a: not_found()
    entitled, _ = is_entitled_to_asset(db, user.id, a)
    if not entitled:
        forbidden("Not entitled to download")
    object_key = a.model_object_key
    normalized = _normalize_format(format)
    if normalized:
        format_keys = a.meta_json.get("format_keys") if isinstance(a.meta_json, dict) else None
        if isinstance(format_keys, dict):
            mapped_key = format_keys.get(normalized) or format_keys.get(normalized.lstrip("."))
            if isinstance(mapped_key, str) and mapped_key:
                object_key = mapped_key
        if object_key == a.model_object_key:
            current_ext = _extension_from_key(a.model_object_key)
            if current_ext != normalized:
                bad_request("Format not available")
    url = object_key if object_key.startswith(("http://", "https://")) else s3.presign_get(settings.s3_bucket_marketplace_models, object_key, expires=900)
    db.add(Download(user_id=user.id, asset_id=a.id))
    db.commit()
    notify.notify_marketplace_download(db, a.creator_id, user.id, a.id, a.title, _actor_name(db, user.id))
    return DownloadOut(url=url, expires_in=900)
