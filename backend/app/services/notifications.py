"""In-app notification service.

The `notifications` table stores a free-form ``payload_json`` blob alongside a
``type`` and ``user_id`` (see ``app/db/models/social.py``). To avoid any schema
change we keep the human-facing fields (``title``, ``body``, ``action_url`` and
an optional ``entity`` pointer) inside that payload — which is exactly what the
Flutter bell already reads (it looks for ``title`` then ``body``/``message``).

Every helper is **best-effort**: a failure to create a notification must never
break the job, like, or download that triggered it. Each writer commits the
notification on its own session so a notify error can never poison the caller's
transaction. We never place secrets or presigned URLs in a payload — only plain
text and an in-app (relative) ``action_url``.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from sqlalchemy.orm import Session

from app.db.models.social import Notification
from app.db.session import SessionLocal

log = logging.getLogger(__name__)


def create_notification(
    db: Session | None,
    user_id: uuid.UUID | str,
    type: str,
    title: str,
    body: str | None = None,
    entity_type: str | None = None,
    entity_id: uuid.UUID | str | None = None,
    action_url: str | None = None,
    meta: dict[str, Any] | None = None,
) -> Notification | None:
    """Create one notification for ``user_id``.

    Returns the created row, or ``None`` if anything went wrong (logged, never
    raised). When ``db`` is provided the notification is committed on that
    session; when it is ``None`` (e.g. from a Celery worker) a short-lived
    session is opened and closed here.
    """
    payload: dict[str, Any] = {"title": title}
    if body:
        payload["body"] = body
    if action_url:
        payload["action_url"] = action_url
    if entity_type:
        payload["entity_type"] = entity_type
    if entity_id is not None:
        payload["entity_id"] = str(entity_id)
    if meta:
        # Never let caller-supplied meta clobber the structured keys above.
        for k, v in meta.items():
            payload.setdefault(k, v)

    owns_session = db is None
    session = db or SessionLocal()
    try:
        notif = Notification(user_id=user_id, type=type, payload_json=payload)
        session.add(notif)
        session.commit()
        return notif
    except Exception:  # pragma: no cover - defensive, must never break caller
        log.exception("Failed to create notification type=%s user=%s", type, user_id)
        try:
            session.rollback()
        except Exception:
            pass
        return None
    finally:
        if owns_session:
            session.close()


# ── AI generation jobs ─────────────────────────────────────────────────────

def notify_ai_job_completed(db: Session | None, user_id, job_id) -> None:
    create_notification(
        db, user_id,
        type="ai_job_completed",
        title="3D model ready",
        body="Your AI generation finished successfully.",
        entity_type="ai_job", entity_id=job_id,
        action_url=f"/jobs/{job_id}",
    )


def notify_ai_job_failed(db: Session | None, user_id, job_id, error: str | None = None) -> None:
    create_notification(
        db, user_id,
        type="ai_job_failed",
        title="AI generation failed",
        body=(error or "Your AI generation could not be completed.")[:280],
        entity_type="ai_job", entity_id=job_id,
        action_url=f"/jobs/{job_id}",
    )


# ── Scan / photogrammetry jobs ─────────────────────────────────────────────

def notify_scan_completed(db: Session | None, user_id, job_id) -> None:
    create_notification(
        db, user_id,
        type="scan_completed",
        title="Scan reconstruction ready",
        body="Your photogrammetry scan finished successfully.",
        entity_type="scan_job", entity_id=job_id,
        action_url=f"/scans/{job_id}",
    )


def notify_scan_failed(db: Session | None, user_id, job_id, error: str | None = None) -> None:
    create_notification(
        db, user_id,
        type="scan_failed",
        title="Scan reconstruction failed",
        body=(error or "Your photogrammetry scan could not be completed.")[:280],
        entity_type="scan_job", entity_id=job_id,
        action_url=f"/scans/{job_id}",
    )


# ── Marketplace ────────────────────────────────────────────────────────────

def notify_marketplace_like(db: Session, creator_id, actor_id, asset_id, asset_title: str, actor_name: str | None = None) -> None:
    if str(creator_id) == str(actor_id):
        return
    who = actor_name or "Someone"
    create_notification(
        db, creator_id,
        type="asset_like",
        title="New like on your asset",
        body=f"{who} liked \"{asset_title}\".",
        entity_type="asset", entity_id=asset_id,
        action_url=f"/marketplace/{asset_id}",
    )


def notify_marketplace_save(db: Session, creator_id, actor_id, asset_id, asset_title: str, actor_name: str | None = None) -> None:
    if str(creator_id) == str(actor_id):
        return
    who = actor_name or "Someone"
    create_notification(
        db, creator_id,
        type="asset_save",
        title="Someone saved your asset",
        body=f"{who} saved \"{asset_title}\".",
        entity_type="asset", entity_id=asset_id,
        action_url=f"/marketplace/{asset_id}",
    )


def notify_marketplace_download(db: Session, creator_id, actor_id, asset_id, asset_title: str, actor_name: str | None = None) -> None:
    if str(creator_id) == str(actor_id):
        return
    who = actor_name or "Someone"
    create_notification(
        db, creator_id,
        type="asset_download",
        title="Your asset was downloaded",
        body=f"{who} downloaded \"{asset_title}\".",
        entity_type="asset", entity_id=asset_id,
        action_url=f"/marketplace/{asset_id}",
    )


# ── Freelance / orders (wired in a later phase) ────────────────────────────

def notify_order_update(db: Session, user_id, order_id, title: str, body: str | None = None, type: str = "order_update") -> None:
    create_notification(
        db, user_id,
        type=type,
        title=title,
        body=body,
        entity_type="order", entity_id=order_id,
        action_url=f"/orders/{order_id}",
    )


# ── Chat (wired in a later phase) ──────────────────────────────────────────

def notify_new_message(db: Session, recipient_id, conversation_id, sender_name: str | None = None) -> None:
    who = sender_name or "Someone"
    create_notification(
        db, recipient_id,
        type="new_message",
        title="New message",
        body=f"{who} sent you a message.",
        entity_type="conversation", entity_id=conversation_id,
        action_url=f"/chat/{conversation_id}",
    )
