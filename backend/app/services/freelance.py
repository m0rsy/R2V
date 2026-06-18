from __future__ import annotations

import datetime as dt
import os
import tempfile
import uuid
from decimal import Decimal
from typing import Iterable

from fastapi import UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.errors import bad_request, forbidden
from app.db.models.freelance import APPLICATION_STATUSES, FreelancerApplication
from app.db.models.freelance_market import (
    AVAILABILITY_STATUSES,
    FREELANCE_CATEGORIES,
    ORDER_STATUSES,
    PROFILE_STATUSES,
    SERVICE_STATUSES,
    FreelanceChatMessage,
    FreelanceOrder,
    FreelanceReview,
    FreelanceService,
    FreelancerProfile,
)
from app.db.models.user import User, UserProfile
from app.services.s3 import s3


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
AUDIO_EXTS = {".mp3", ".wav", ".m4a", ".ogg", ".webm"}
MODEL_EXTS = {".glb", ".gltf", ".obj", ".fbx", ".blend", ".stl"}
DOC_EXTS = {".zip", ".pdf", ".txt"}
ALLOWED_UPLOAD_EXTS = IMAGE_EXTS | AUDIO_EXTS | MODEL_EXTS | DOC_EXTS


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso(value: dt.datetime | None) -> str | None:
    return value.isoformat() if value else None


def num(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


def clean_list(values: Iterable | None, *, limit: int = 40) -> list[str]:
    out: list[str] = []
    for value in values or []:
        item = str(value).strip()
        if item and item not in out:
            out.append(item)
        if len(out) >= limit:
            break
    return out


def validate_choice(value: str, allowed: tuple[str, ...], field: str) -> str:
    item = (value or "").strip()
    if item not in allowed:
        bad_request(f"Invalid {field}: {item}")
    return item


def category_list() -> list[str]:
    return list(FREELANCE_CATEGORIES)


def user_payloads(db: Session, user_ids: Iterable[uuid.UUID]) -> dict[str, dict]:
    ids = list({uid for uid in user_ids if uid})
    if not ids:
        return {}
    rows = db.execute(
        select(User, UserProfile)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(User.id.in_(ids))
    ).all()
    payloads: dict[str, dict] = {}
    for user, profile in rows:
        username = profile.username if profile else user.email.split("@")[0]
        payloads[str(user.id)] = {
            "id": str(user.id),
            "email": user.email,
            "username": username,
            "display_name": username,
            "avatar_url": profile.avatar_url if profile else None,
            "role": user.role,
        }
    return payloads


def serialize_application(db: Session, app: FreelancerApplication) -> dict:
    user = db.get(User, app.user_id)
    profile = user.profile if user else None
    return {
        "id": str(app.id),
        "user_id": str(app.user_id),
        "email": user.email if user else None,
        "username": profile.username if profile else None,
        "avatar_url": profile.avatar_url if profile else None,
        "full_name": app.full_name,
        "display_name": app.full_name,
        "title": app.title,
        "skills": app.skills if isinstance(app.skills, list) else [],
        "experience": app.experience,
        "portfolio_links": app.portfolio_links if isinstance(app.portfolio_links, list) else [],
        "expected_price_range": app.expected_price_range,
        "message": app.message,
        "status": app.status,
        "admin_note": app.admin_note,
        "reviewed_at": iso(app.reviewed_at),
        "created_at": iso(app.created_at),
        "updated_at": iso(app.updated_at),
    }


def serialize_profile(db: Session, profile: FreelancerProfile, *, include_services: bool = False) -> dict:
    payload = user_payloads(db, [profile.user_id]).get(str(profile.user_id), {})
    data = {
        "id": str(profile.id),
        "user_id": str(profile.user_id),
        "username": payload.get("username"),
        "email": payload.get("email", ""),
        "display_name": profile.display_name,
        "title": profile.title,
        "role": profile.title,
        "bio": profile.bio,
        "skills": profile.skills if isinstance(profile.skills, list) else [],
        "categories": profile.categories if isinstance(profile.categories, list) else [],
        "category": (profile.categories or [None])[0] if isinstance(profile.categories, list) else None,
        "hourly_rate": num(profile.hourly_rate),
        "starting_price": num(profile.starting_price),
        "profile_image": profile.profile_image,
        "avatar_url": profile.profile_image or payload.get("avatar_url"),
        "cover_url": None,
        "portfolio_links": profile.portfolio_links if isinstance(profile.portfolio_links, list) else [],
        "portfolio": profile.portfolio_links if isinstance(profile.portfolio_links, list) else [],
        "status": profile.status,
        "availability": profile.availability,
        "rating_average": num(profile.rating_average) or 0,
        "rating_avg": num(profile.rating_average) or 0,
        "rating": num(profile.rating_average) or 0,
        "rating_count": profile.rating_count,
        "reviews": profile.rating_count,
        "reviews_count": profile.rating_count,
        "completed_jobs_count": profile.completed_jobs_count,
        "completed_jobs": profile.completed_jobs_count,
        "featured": (num(profile.rating_average) or 0) >= 4.8 or profile.completed_jobs_count >= 10,
        "created_at": iso(profile.created_at),
        "updated_at": iso(profile.updated_at),
    }
    if include_services:
        data["services"] = [serialize_service(db, svc) for svc in profile.services]
        data["reviews"] = [
            serialize_review(db, review)
            for review in db.execute(
                select(FreelanceReview)
                .where(FreelanceReview.freelancer_id == profile.id)
                .order_by(FreelanceReview.created_at.desc())
                .limit(50)
            ).scalars()
        ]
    return data


def serialize_service(db: Session, service: FreelanceService) -> dict:
    profile = db.get(FreelancerProfile, service.freelancer_id)
    return {
        "id": str(service.id),
        "freelancer_id": str(service.freelancer_id),
        "freelancer": serialize_profile(db, profile) if profile else None,
        "title": service.title,
        "description": service.description,
        "category": service.category,
        "tags": service.tags if isinstance(service.tags, list) else [],
        "starting_price": num(service.starting_price) or 0,
        "delivery_days": service.delivery_days,
        "revisions": service.revisions,
        "file_formats": service.file_formats if isinstance(service.file_formats, list) else [],
        "images": service.images if isinstance(service.images, list) else [],
        "status": service.status,
        "created_at": iso(service.created_at),
        "updated_at": iso(service.updated_at),
    }


def serialize_order(db: Session, order: FreelanceOrder, viewer: User | None = None) -> dict:
    profile = db.get(FreelancerProfile, order.freelancer_id)
    service = db.get(FreelanceService, order.service_id) if order.service_id else None
    payloads = user_payloads(db, [order.client_id, profile.user_id if profile else order.client_id])
    role = None
    if viewer:
        if viewer.id == order.client_id:
            role = "client"
        elif profile and viewer.id == profile.user_id:
            role = "freelancer"
        elif viewer.role in ("admin", "super_admin"):
            role = "admin"
    reviewed = False
    if viewer:
        reviewed = db.execute(
            select(FreelanceReview.id).where(
                FreelanceReview.order_id == order.id,
                FreelanceReview.client_id == viewer.id,
            )
        ).first() is not None
    return {
        "id": str(order.id),
        "client_id": str(order.client_id),
        "freelancer_id": str(order.freelancer_id),
        "freelancer_user_id": str(profile.user_id) if profile else None,
        "service_id": str(order.service_id) if order.service_id else None,
        "client": payloads.get(str(order.client_id)),
        "freelancer": serialize_profile(db, profile) if profile else None,
        "service": serialize_service(db, service) if service else None,
        "title": order.title,
        "requirements": order.requirements,
        "description": order.requirements,
        "budget": num(order.budget) or 0,
        "price": num(order.budget) or 0,
        "deadline": iso(order.deadline),
        "attachments": order.attachments if isinstance(order.attachments, list) else [],
        "status": order.status,
        "delivery_files": order.delivery_files if isinstance(order.delivery_files, list) else [],
        "deliverables": order.delivery_files if isinstance(order.delivery_files, list) else [],
        "revision_note": order.revision_note,
        "dispute_reason": order.dispute_reason,
        "role": role,
        "can_review": role == "client" and order.status == "completed" and not reviewed,
        "has_reviewed": reviewed,
        "created_at": iso(order.created_at),
        "updated_at": iso(order.updated_at),
        "completed_at": iso(order.completed_at),
    }


def serialize_message(db: Session, message: FreelanceChatMessage, viewer: User) -> dict:
    payload = user_payloads(db, [message.sender_id]).get(str(message.sender_id), {})
    return {
        "id": str(message.id),
        "order_id": str(message.order_id),
        "conversation_id": str(message.order_id),
        "sender_id": str(message.sender_id),
        "sender": payload,
        "message": message.message or "",
        "body": message.message or "",
        "attachments": message.attachments if isinstance(message.attachments, list) else [],
        "voice_note_url": message.voice_note_url,
        "message_type": "attachment" if message.attachments else "text",
        "is_mine": message.sender_id == viewer.id,
        "created_at": iso(message.created_at),
        "read_at": iso(message.read_at),
    }


def serialize_review(db: Session, review: FreelanceReview) -> dict:
    payload = user_payloads(db, [review.client_id]).get(str(review.client_id), {})
    return {
        "id": str(review.id),
        "order_id": str(review.order_id),
        "client_id": str(review.client_id),
        "reviewer_id": str(review.client_id),
        "reviewer": payload,
        "freelancer_id": str(review.freelancer_id),
        "reviewee_id": str(review.freelancer_id),
        "rating": review.rating,
        "quality_rating": review.quality_rating,
        "communication_rating": review.communication_rating,
        "delivery_rating": review.delivery_rating,
        "comment": review.comment,
        "created_at": iso(review.created_at),
    }


def require_approved_profile(db: Session, user: User) -> FreelancerProfile:
    profile = db.execute(
        select(FreelancerProfile).where(FreelancerProfile.user_id == user.id)
    ).scalar_one_or_none()
    if not profile or profile.status != "approved":
        forbidden("Only approved freelancers can perform this action")
    return profile


def order_role(order: FreelanceOrder, profile: FreelancerProfile | None, user: User) -> str:
    if user.id == order.client_id:
        return "client"
    if profile and user.id == profile.user_id:
        return "freelancer"
    if user.role in ("admin", "super_admin"):
        return "admin"
    forbidden("You do not have access to this order")


def recompute_profile_stats(db: Session, profile: FreelancerProfile) -> None:
    avg, count = db.execute(
        select(func.avg(FreelanceReview.rating), func.count(FreelanceReview.id)).where(
            FreelanceReview.freelancer_id == profile.id
        )
    ).one()
    completed = db.execute(
        select(func.count(FreelanceOrder.id)).where(
            FreelanceOrder.freelancer_id == profile.id,
            FreelanceOrder.status == "completed",
        )
    ).scalar_one()
    profile.rating_average = round(float(avg), 2) if avg is not None else 0
    profile.rating_count = int(count or 0)
    profile.completed_jobs_count = int(completed or 0)
    db.flush()


async def upload_to_freelance_bucket(
    file: UploadFile,
    *,
    prefix: str,
    allow_audio: bool = True,
) -> dict:
    raw = await file.read()
    size = len(raw)
    if size == 0:
        bad_request("Empty file")
    if size > settings.chat_attachment_max_bytes:
        bad_request(f"File too large (max {settings.chat_attachment_max_bytes // (1024 * 1024)} MB)")
    name = file.filename or "upload"
    ext = os.path.splitext(name)[1].lower()
    allowed = ALLOWED_UPLOAD_EXTS if allow_audio else (ALLOWED_UPLOAD_EXTS - AUDIO_EXTS)
    if ext not in allowed:
        bad_request(f"Unsupported file type: {ext or 'unknown'}")
    mime = (file.content_type or "application/octet-stream").lower()
    storage_key = f"freelance/{prefix.strip('/')}/{uuid.uuid4()}_{name}"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(raw)
            tmp_path = tmp.name
        s3.upload_file(tmp_path, settings.s3_bucket_chat_attachments, storage_key, content_type=mime)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
    return {
        "storage_key": storage_key,
        "url": s3.presign_get(
            settings.s3_bucket_chat_attachments,
            storage_key,
            expires=settings.chat_attachment_url_expires_s,
        ),
        "file_name": name,
        "mime_type": mime,
        "file_size": size,
        "attachment_type": classify_file(name),
    }


def classify_file(file_name: str) -> str:
    ext = os.path.splitext(file_name or "")[1].lower()
    if ext in IMAGE_EXTS:
        return "image"
    if ext in AUDIO_EXTS:
        return "audio"
    if ext in MODEL_EXTS:
        return "model"
    if ext in DOC_EXTS:
        return "document"
    return "other"


def validate_application_status(status: str) -> str:
    return validate_choice(status, APPLICATION_STATUSES, "application status")


def validate_profile_status(status: str) -> str:
    return validate_choice(status, PROFILE_STATUSES, "profile status")


def validate_availability(status: str) -> str:
    return validate_choice(status, AVAILABILITY_STATUSES, "availability")


def validate_service_status(status: str) -> str:
    return validate_choice(status, SERVICE_STATUSES, "service status")


def validate_order_status(status: str) -> str:
    return validate_choice(status, ORDER_STATUSES, "order status")
