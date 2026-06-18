from __future__ import annotations

from pydantic import BaseModel, Field


class ChatUserOut(BaseModel):
    id: str
    username: str
    avatar_url: str | None = None
    role: str


class MessageAttachmentOut(BaseModel):
    id: str
    url: str | None = None
    file_name: str
    mime_type: str
    file_size: int = 0
    attachment_type: str = "other"
    duration_seconds: int | None = None
    created_at: str


class ChatMessageOut(BaseModel):
    id: str
    conversation_id: str
    body: str = ""
    message_type: str = "text"
    created_at: str
    edited_at: str | None = None
    is_mine: bool = False
    sender: ChatUserOut
    attachments: list[MessageAttachmentOut] = []


class ConversationCreateIn(BaseModel):
    participant_ids: list[str] = Field(min_length=1)


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


class ConversationOut(BaseModel):
    id: str
    title: str | None = None
    is_group: bool = False
    participants: list[ChatUserOut]
    last_message: ChatMessageOut | None = None
    last_message_at: str | None = None
    unread_count: int = 0
    updated_at: str


class ConversationDetailOut(BaseModel):
    conversation: ConversationOut
    messages: list[ChatMessageOut]
    has_more: bool = False
