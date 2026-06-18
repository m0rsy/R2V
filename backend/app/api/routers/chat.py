from __future__ import annotations

import datetime as dt
import os
import tempfile
import uuid

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from sqlalchemy import desc, func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.api.schemas.chat import (
    ChatUserOut,
    ConversationCreateIn,
    ConversationDetailOut,
    ConversationOut,
    MessageIn,
)
from app.core.config import settings
from app.core.errors import bad_request, forbidden, not_found
from app.db.models.chat import (
    ChatMessage,
    Conversation,
    ConversationParticipant,
    MessageAttachment,
)
from app.db.models.user import User, UserProfile
from app.services import chat as chat_svc
from app.services.s3 import s3

router = APIRouter()

# message shown when the mutual-follow rule blocks a DM
MUTUAL_FOLLOW_ERROR = "You can only message users who follow you back."

# Allowed attachment MIME types by category.
_IMAGE_MIME = {"image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif"}
_DOC_MIME = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/plain",
    "application/zip",
    "application/x-zip-compressed",
}
_AUDIO_MIME = {
    "audio/webm",
    "audio/mpeg",
    "audio/mp3",
    "audio/mp4",
    "audio/wav",
    "audio/x-wav",
    "audio/ogg",
    "audio/aac",
}
# 3D model files frequently arrive as octet-stream, so we also gate by extension.
_MODEL_EXT = {".glb", ".gltf", ".obj", ".fbx", ".stl"}
_MODEL_MIME = {"model/gltf-binary", "model/gltf+json", "application/octet-stream"}


def _parse_uuid(value: str, message: str = "Invalid id") -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError):
        bad_request(message)


def _direct_peer_id(db: Session, conv: Conversation, me: uuid.UUID) -> uuid.UUID | None:
    """The other participant in a 1:1 direct conversation, if any."""
    if conv.is_group:
        return None
    ids = db.execute(
        select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conv.id,
            ConversationParticipant.user_id != me,
        )
    ).scalars().all()
    return ids[0] if len(ids) == 1 else None


def _enforce_can_message_direct(db: Session, conv: Conversation, me: uuid.UUID) -> None:
    """Block sending in a peer DM unless both users mutually follow.

    Only applies to kind="direct" 1:1 conversations. Freelance channels and
    group conversations are exempt.
    """
    if conv.is_group or conv.kind != "direct":
        return
    peer = _direct_peer_id(db, conv, me)
    if peer is None:
        return
    if not chat_svc.can_message(db, me, peer):
        forbidden(MUTUAL_FOLLOW_ERROR)


def _classify_attachment(file_name: str, mime: str, requested_kind: str) -> str:
    ext = os.path.splitext(file_name or "")[1].lower()
    if requested_kind == "voice" or mime in _AUDIO_MIME:
        return "voice"
    if mime in _IMAGE_MIME:
        return "image"
    if ext in _MODEL_EXT:
        return "model"
    if mime in _DOC_MIME:
        return "document"
    return "other"


@router.get("/users", response_model=list[ChatUserOut])
def chat_users(
    search: str = Query(default="", max_length=120),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Mutual followers available to start a conversation with (excludes self).

    Direct messaging is restricted to users who follow each other, so search
    only returns people the caller can actually message.
    """
    mutual_ids = chat_svc.mutual_follower_ids(db, user.id)
    if not mutual_ids:
        return []

    stmt = (
        select(User, UserProfile)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(
            User.id != user.id,
            User.is_active.is_(True),
            User.id.in_(mutual_ids),
        )
    )
    term = search.strip()
    if term:
        like = f"%{term}%"
        stmt = stmt.where(or_(UserProfile.username.ilike(like), User.email.ilike(like)))
    stmt = stmt.order_by(UserProfile.username).limit(30)
    rows = db.execute(stmt).all()
    return [
        ChatUserOut(
            id=str(u.id),
            username=p.username if p else u.email.split("@")[0],
            avatar_url=p.avatar_url if p else None,
            role=u.role,
        )
        for u, p in rows
    ]


def _serialize_conversation(
    db: Session, conv: Conversation, current_user_id: uuid.UUID, last_read_at: dt.datetime | None
) -> ConversationOut:
    participant_ids = db.execute(
        select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conv.id
        )
    ).scalars().all()
    payloads = chat_svc.user_payloads(db, participant_ids)

    last_msg = db.execute(
        select(ChatMessage)
        .where(ChatMessage.conversation_id == conv.id)
        .order_by(desc(ChatMessage.created_at))
        .limit(1)
    ).scalars().first()

    last_message = None
    if last_msg:
        last_message = chat_svc.serialize_message(last_msg, payloads, current_user_id)

    return ConversationOut(
        id=str(conv.id),
        title=conv.title,
        is_group=conv.is_group,
        participants=[ChatUserOut(**payloads[pid]) for pid in payloads],
        last_message=last_message,
        last_message_at=conv.last_message_at.isoformat() if conv.last_message_at else None,
        unread_count=chat_svc.unread_count(db, conv.id, current_user_id, last_read_at),
        updated_at=conv.updated_at.isoformat(),
    )


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = db.execute(
        select(ConversationParticipant.conversation_id, ConversationParticipant.last_read_at).where(
            ConversationParticipant.user_id == user.id
        )
    ).all()
    last_read = {cid: lra for cid, lra in rows}
    if not last_read:
        return []

    convs = db.execute(
        select(Conversation)
        .where(Conversation.id.in_(list(last_read.keys())))
        .order_by(desc(func.coalesce(Conversation.last_message_at, Conversation.updated_at)))
        .limit(100)
    ).scalars().all()

    return [_serialize_conversation(db, conv, user.id, last_read.get(conv.id)) for conv in convs]


@router.post("/conversations", response_model=ConversationOut)
def create_conversation(
    payload: ConversationCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    other_ids: list[uuid.UUID] = []
    for raw in payload.participant_ids:
        pid = _parse_uuid(raw, "Invalid participant id")
        if pid != user.id and pid not in other_ids:
            other_ids.append(pid)
    if not other_ids:
        bad_request("Provide at least one other participant")

    # All targets must be active users.
    found = db.execute(
        select(User.id).where(User.id.in_(other_ids), User.is_active.is_(True))
    ).scalars().all()
    if len(found) != len(other_ids):
        bad_request("One or more participants are unavailable")

    # Mutual-follow rule: you can only start a direct chat with people who
    # follow you back. Enforced server-side so it cannot be bypassed.
    for pid in other_ids:
        if not chat_svc.can_message(db, user.id, pid):
            forbidden(MUTUAL_FOLLOW_ERROR)

    if len(other_ids) == 1:
        conv = chat_svc.get_or_create_direct(db, user.id, other_ids[0])
    else:
        conv = Conversation(is_group=True)
        db.add(conv)
        db.flush()
        members = [user.id, *other_ids]
        db.add_all(
            [ConversationParticipant(conversation_id=conv.id, user_id=mid) for mid in members]
        )
        db.flush()
    db.commit()
    me_part = db.execute(
        select(ConversationParticipant.last_read_at).where(
            ConversationParticipant.conversation_id == conv.id,
            ConversationParticipant.user_id == user.id,
        )
    ).scalar_one_or_none()
    return _serialize_conversation(db, conv, user.id, me_part)


def _require_participant(db: Session, conversation_id: str, user: User) -> Conversation:
    conv_id = _parse_uuid(conversation_id, "Invalid conversation id")
    conv = db.get(Conversation, conv_id)
    if not conv:
        not_found("Conversation not found")
    if not chat_svc.is_participant(db, conv.id, user.id):
        forbidden("You are not a participant in this conversation")
    return conv


@router.get("/conversations/{conversation_id}/messages", response_model=ConversationDetailOut)
def get_messages(
    conversation_id: str,
    limit: int = Query(default=50, ge=1, le=100),
    before: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    conv = _require_participant(db, conversation_id, user)

    stmt = select(ChatMessage).where(ChatMessage.conversation_id == conv.id)
    if before:
        try:
            before_dt = dt.datetime.fromisoformat(before)
            stmt = stmt.where(ChatMessage.created_at < before_dt)
        except ValueError:
            bad_request("Invalid 'before' cursor")
    stmt = stmt.order_by(desc(ChatMessage.created_at)).limit(limit + 1)
    rows = db.execute(stmt).scalars().all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    rows.reverse()  # chronological order for display

    participant_ids = db.execute(
        select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conv.id
        )
    ).scalars().all()
    payloads = chat_svc.user_payloads(db, participant_ids)

    # Mark conversation read up to now for the current user.
    part = db.execute(
        select(ConversationParticipant).where(
            ConversationParticipant.conversation_id == conv.id,
            ConversationParticipant.user_id == user.id,
        )
    ).scalar_one_or_none()
    if part:
        part.last_read_at = dt.datetime.now(dt.timezone.utc)
        db.commit()

    messages = [chat_svc.serialize_message(m, payloads, user.id) for m in rows]
    conversation_out = _serialize_conversation(db, conv, user.id, part.last_read_at if part else None)
    return ConversationDetailOut(
        conversation=conversation_out, messages=messages, has_more=has_more
    )


@router.post("/conversations/{conversation_id}/messages", response_model=ConversationDetailOut)
def send_message(
    conversation_id: str,
    payload: MessageIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    conv = _require_participant(db, conversation_id, user)
    _enforce_can_message_direct(db, conv, user.id)
    msg = chat_svc.post_message(db, conv, user.id, payload.text)
    db.commit()
    db.refresh(msg)

    participant_ids = db.execute(
        select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conv.id
        )
    ).scalars().all()
    payloads = chat_svc.user_payloads(db, participant_ids)
    conversation_out = _serialize_conversation(db, conv, user.id, None)
    return ConversationDetailOut(
        conversation=conversation_out,
        messages=[chat_svc.serialize_message(msg, payloads, user.id)],
        has_more=False,
    )


@router.post("/conversations/{conversation_id}/read", response_model=ConversationOut)
def mark_read(
    conversation_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Explicitly mark a conversation read up to now for the current user."""
    conv = _require_participant(db, conversation_id, user)
    part = db.execute(
        select(ConversationParticipant).where(
            ConversationParticipant.conversation_id == conv.id,
            ConversationParticipant.user_id == user.id,
        )
    ).scalar_one_or_none()
    if part:
        part.last_read_at = dt.datetime.now(dt.timezone.utc)
        db.commit()
    return _serialize_conversation(db, conv, user.id, part.last_read_at if part else None)


@router.post("/conversations/{conversation_id}/attachments", response_model=ConversationDetailOut)
@router.post("/conversations/{conversation_id}/voice-note", response_model=ConversationDetailOut)
async def upload_attachment(
    conversation_id: str,
    file: UploadFile = File(...),
    text: str | None = Form(default=None),
    kind: str = Form(default="auto"),
    duration_seconds: int | None = Form(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Send a message with a single file attachment (image / document / 3D / voice).

    Same security as text: participant-only, mutual-follow for direct DMs,
    plus MIME + size validation. Files are stored in the private chat bucket;
    only short-lived presigned URLs are ever returned.
    """
    conv = _require_participant(db, conversation_id, user)
    _enforce_can_message_direct(db, conv, user.id)

    raw = await file.read()
    size = len(raw)
    if size == 0:
        bad_request("Empty file")

    mime = (file.content_type or "application/octet-stream").lower()
    file_name = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S_") + (file.filename or "attachment")
    requested = (kind or "auto").lower()
    attachment_type = _classify_attachment(file.filename or "", mime, requested)

    is_voice = attachment_type == "voice"

    # Validate MIME / extension by category.
    ext = os.path.splitext(file.filename or "")[1].lower()
    allowed = (
        mime in _AUDIO_MIME
        or mime in _IMAGE_MIME
        or mime in _DOC_MIME
        or (ext in _MODEL_EXT and mime in _MODEL_MIME)
    )
    if not allowed:
        bad_request(f"Unsupported file type: {mime or ext or 'unknown'}")

    # Size limits: voice notes are capped tighter than general attachments.
    max_bytes = settings.chat_voice_max_bytes if is_voice else settings.chat_attachment_max_bytes
    if size > max_bytes:
        bad_request(f"File too large (max {max_bytes // (1024 * 1024)} MB)")

    if is_voice and duration_seconds and duration_seconds > settings.chat_voice_max_seconds:
        bad_request(f"Voice note too long (max {settings.chat_voice_max_seconds}s)")

    # Decide message type.
    has_text = bool((text or "").strip())
    if is_voice:
        message_type = "voice"
    elif has_text:
        message_type = "mixed"
    else:
        message_type = "attachment"

    msg = chat_svc.post_message(db, conv, user.id, text, message_type=message_type)

    storage_key = f"chat/{conv.id}/{msg.id}/{file_name}"

    # Stage to a temp file and upload via the shared S3 client.
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

    attachment = MessageAttachment(
        message_id=msg.id,
        storage_key=storage_key,
        file_name=file.filename or file_name,
        mime_type=mime,
        file_size=size,
        attachment_type=attachment_type,
        duration_seconds=duration_seconds if is_voice else None,
    )
    db.add(attachment)
    db.commit()
    db.refresh(msg)

    participant_ids = db.execute(
        select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conv.id
        )
    ).scalars().all()
    payloads = chat_svc.user_payloads(db, participant_ids)
    conversation_out = _serialize_conversation(db, conv, user.id, None)
    return ConversationDetailOut(
        conversation=conversation_out,
        messages=[chat_svc.serialize_message(msg, payloads, user.id)],
        has_more=False,
    )
