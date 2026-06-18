from __future__ import annotations
import datetime as dt
from fastapi import APIRouter, Depends
from sqlalchemy import select, desc
from sqlalchemy.orm import Session
from app.api.deps import get_db, get_current_user
from app.api.schemas.ai_chat import (
    AiConversationOut,
    AiConversationDetailOut,
    AiConversationCreateIn,
    AiConversationUpdateIn,
    AiMessageOut,
    AiMessageCreateIn,
)
from app.core.errors import not_found, forbidden, bad_request
from app.db.models.ai_chat import AiConversation, AiMessage

router = APIRouter()


def _conv_out(c: AiConversation) -> AiConversationOut:
    return AiConversationOut(
        id=str(c.id),
        title=c.title,
        last_job_id=str(c.last_job_id) if c.last_job_id else None,
        created_at=c.created_at.isoformat(),
        updated_at=c.updated_at.isoformat(),
    )


def _msg_out(m: AiMessage) -> AiMessageOut:
    return AiMessageOut(
        id=str(m.id),
        role=m.role,
        text=m.text,
        model_url=m.model_url,
        job_id=str(m.job_id) if m.job_id else None,
        meta=m.meta or {},
        created_at=m.created_at.isoformat(),
    )


def _owned_conversation(conv_id: str, db: Session, user) -> AiConversation:
    """Fetch a conversation and enforce that it belongs to the caller. Every
    chat route funnels through here so a user can never touch another user's
    AI history."""
    c = db.get(AiConversation, conv_id)
    if not c:
        not_found("Conversation not found")
    if c.user_id != user.id:
        forbidden()
    return c


@router.get("/chats", response_model=list[AiConversationOut])
def list_chats(limit: int = 50, offset: int = 0, db: Session = Depends(get_db), user=Depends(get_current_user)):
    stmt = (
        select(AiConversation)
        .where(AiConversation.user_id == user.id)
        .order_by(desc(AiConversation.updated_at))
        .limit(limit)
        .offset(offset)
    )
    return [_conv_out(c) for c in db.execute(stmt).scalars().all()]


@router.post("/chats", response_model=AiConversationOut)
def create_chat(payload: AiConversationCreateIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = AiConversation(user_id=user.id, title=(payload.title or None))
    db.add(c)
    db.commit()
    db.refresh(c)
    return _conv_out(c)


@router.get("/chats/{chat_id}", response_model=AiConversationDetailOut)
def get_chat(chat_id: str, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = _owned_conversation(chat_id, db, user)
    msgs = db.execute(
        select(AiMessage).where(AiMessage.conversation_id == c.id).order_by(AiMessage.created_at)
    ).scalars().all()
    base = _conv_out(c)
    return AiConversationDetailOut(**base.model_dump(), messages=[_msg_out(m) for m in msgs])


@router.get("/chats/{chat_id}/messages", response_model=list[AiMessageOut])
def list_messages(chat_id: str, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = _owned_conversation(chat_id, db, user)
    msgs = db.execute(
        select(AiMessage).where(AiMessage.conversation_id == c.id).order_by(AiMessage.created_at)
    ).scalars().all()
    return [_msg_out(m) for m in msgs]


@router.post("/chats/{chat_id}/messages", response_model=AiMessageOut)
def add_message(chat_id: str, payload: AiMessageCreateIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = _owned_conversation(chat_id, db, user)
    role = payload.role if payload.role in ("user", "assistant") else "user"
    if not (payload.text or payload.model_url):
        bad_request("Message must have text or a model_url")
    m = AiMessage(
        conversation_id=c.id,
        role=role,
        text=payload.text,
        model_url=payload.model_url,
        job_id=payload.job_id,
        meta=payload.meta or {},
    )
    db.add(m)
    # Bump the parent thread so it sorts to the top and tracks the latest job.
    c.updated_at = dt.datetime.now(dt.timezone.utc)
    if payload.job_id:
        c.last_job_id = payload.job_id
    db.commit()
    db.refresh(m)
    return _msg_out(m)


@router.patch("/chats/{chat_id}", response_model=AiConversationOut)
def update_chat(chat_id: str, payload: AiConversationUpdateIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = _owned_conversation(chat_id, db, user)
    data = payload.model_dump(exclude_unset=True)
    if "title" in data:
        c.title = data["title"]
    if "last_job_id" in data:
        c.last_job_id = data["last_job_id"]
    c.updated_at = dt.datetime.now(dt.timezone.utc)
    db.commit()
    db.refresh(c)
    return _conv_out(c)


@router.delete("/chats/{chat_id}")
def delete_chat(chat_id: str, db: Session = Depends(get_db), user=Depends(get_current_user)):
    c = _owned_conversation(chat_id, db, user)
    db.delete(c)  # cascades to ai_messages
    db.commit()
    return {"detail": "ok"}
