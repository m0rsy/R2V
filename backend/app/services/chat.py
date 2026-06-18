from __future__ import annotations

"""Shared chat helpers used by the chat router and the freelance workspace.

Centralises conversation lookup/creation, participant checks, and serialization
so both the dedicated chat API and the freelance "message a freelancer" flow
read and write the same real data.
"""

import datetime as dt
import uuid
from typing import Iterable

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models.chat import (
    ChatMessage,
    Conversation,
    ConversationParticipant,
    MessageAttachment,
)
from app.db.models.social import Follow
from app.db.models.user import User, UserProfile
from app.services.s3 import s3


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(value: dt.datetime | None) -> str | None:
    return value.isoformat() if value else None


def user_payloads(db: Session, user_ids: Iterable[uuid.UUID]) -> dict[str, dict]:
    """Return {user_id: {id, username, avatar_url, role}} for the given ids."""
    ids = list({uid for uid in user_ids})
    if not ids:
        return {}
    rows = db.execute(
        select(User, UserProfile)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(User.id.in_(ids))
    ).all()
    out: dict[str, dict] = {}
    for user, profile in rows:
        out[str(user.id)] = {
            "id": str(user.id),
            "username": profile.username if profile else user.email.split("@")[0],
            "avatar_url": profile.avatar_url if profile else None,
            "role": user.role,
        }
    return out


def are_mutual_followers(db: Session, user_a: uuid.UUID, user_b: uuid.UUID) -> bool:
    """True only when A follows B AND B follows A."""
    if user_a == user_b:
        return False
    rows = db.execute(
        select(Follow.follower_id, Follow.following_id).where(
            ((Follow.follower_id == user_a) & (Follow.following_id == user_b))
            | ((Follow.follower_id == user_b) & (Follow.following_id == user_a))
        )
    ).all()
    pairs = {(f, g) for f, g in rows}
    return (user_a, user_b) in pairs and (user_b, user_a) in pairs


def can_message(db: Session, user_id: uuid.UUID, target_user_id: uuid.UUID) -> bool:
    """A user may DM another only if they mutually follow each other."""
    return are_mutual_followers(db, user_id, target_user_id)


def mutual_follower_ids(db: Session, user_id: uuid.UUID) -> set[uuid.UUID]:
    """Set of user ids that mutually follow `user_id` (I follow them AND they follow me)."""
    follow_me = select(Follow.follower_id).where(Follow.following_id == user_id)
    rows = db.execute(
        select(Follow.following_id).where(
            Follow.follower_id == user_id,
            Follow.following_id.in_(follow_me),
        )
    ).scalars().all()
    return set(rows)


def is_participant(db: Session, conversation_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    row = db.execute(
        select(ConversationParticipant.id).where(
            ConversationParticipant.conversation_id == conversation_id,
            ConversationParticipant.user_id == user_id,
        )
    ).first()
    return row is not None


def get_or_create_direct(
    db: Session, user_a: uuid.UUID, user_b: uuid.UUID, kind: str = "direct"
) -> Conversation:
    """Return the existing 1:1 conversation between two users, or create one.

    `kind` only applies when a new conversation is created. "freelance"
    conversations are a sanctioned business channel and bypass the
    mutual-follow rule enforced on "direct" peer DMs.
    """
    if user_a == user_b:
        raise ValueError("Cannot create a conversation with yourself")

    a_convs = select(ConversationParticipant.conversation_id).where(
        ConversationParticipant.user_id == user_a
    )
    b_convs = select(ConversationParticipant.conversation_id).where(
        ConversationParticipant.user_id == user_b
    )
    existing = db.execute(
        select(Conversation)
        .where(
            Conversation.is_group.is_(False),
            Conversation.id.in_(a_convs),
            Conversation.id.in_(b_convs),
        )
        .limit(1)
    ).scalars().first()
    if existing:
        return existing

    conv = Conversation(is_group=False, kind=kind)
    db.add(conv)
    db.flush()
    db.add_all(
        [
            ConversationParticipant(conversation_id=conv.id, user_id=user_a),
            ConversationParticipant(conversation_id=conv.id, user_id=user_b),
        ]
    )
    db.flush()
    return conv


def attachment_url(storage_key: str) -> str | None:
    """Short-lived presigned GET URL for an attachment. Never exposes the key path."""
    try:
        return s3.presign_get(
            settings.s3_bucket_chat_attachments,
            storage_key,
            expires=settings.chat_attachment_url_expires_s,
        )
    except Exception:
        return None


def serialize_attachment(att: MessageAttachment) -> dict:
    return {
        "id": str(att.id),
        "url": attachment_url(att.storage_key),
        "file_name": att.file_name,
        "mime_type": att.mime_type,
        "file_size": att.file_size,
        "attachment_type": att.attachment_type,
        "duration_seconds": att.duration_seconds,
        "created_at": att.created_at.isoformat(),
    }


def serialize_message(
    msg: ChatMessage, payloads: dict[str, dict], current_user_id: uuid.UUID
) -> dict:
    sender = payloads.get(
        str(msg.sender_id),
        {"id": str(msg.sender_id), "username": "Unknown", "avatar_url": None, "role": "user"},
    )
    attachments = (
        [] if msg.deleted_at else [serialize_attachment(a) for a in (msg.attachments or [])]
    )
    return {
        "id": str(msg.id),
        "conversation_id": str(msg.conversation_id),
        "body": "" if msg.deleted_at else (msg.body or ""),
        "message_type": msg.message_type,
        "created_at": msg.created_at.isoformat(),
        "edited_at": _iso(msg.edited_at),
        "is_mine": msg.sender_id == current_user_id,
        "sender": sender,
        "attachments": attachments,
    }


def post_message(
    db: Session,
    conversation: Conversation,
    sender_id: uuid.UUID,
    text: str | None = None,
    message_type: str = "text",
) -> ChatMessage:
    body = (text or "").strip() or None
    msg = ChatMessage(
        conversation_id=conversation.id,
        sender_id=sender_id,
        body=body,
        message_type=message_type,
    )
    db.add(msg)
    conversation.last_message_at = _utcnow()
    conversation.updated_at = _utcnow()
    db.flush()
    return msg


def unread_count(db: Session, conversation_id: uuid.UUID, user_id: uuid.UUID, last_read_at: dt.datetime | None) -> int:
    stmt = select(func.count()).select_from(ChatMessage).where(
        ChatMessage.conversation_id == conversation_id,
        ChatMessage.sender_id != user_id,
        ChatMessage.deleted_at.is_(None),
    )
    if last_read_at is not None:
        stmt = stmt.where(ChatMessage.created_at > last_read_at)
    return int(db.execute(stmt).scalar_one() or 0)
