from __future__ import annotations
from pydantic import BaseModel, Field


class AiMessageOut(BaseModel):
    id: str
    role: str
    text: str | None = None
    model_url: str | None = None
    job_id: str | None = None
    meta: dict = Field(default_factory=dict)
    created_at: str


class AiConversationOut(BaseModel):
    id: str
    title: str | None = None
    last_job_id: str | None = None
    created_at: str
    updated_at: str


class AiConversationDetailOut(AiConversationOut):
    messages: list[AiMessageOut] = Field(default_factory=list)


class AiConversationCreateIn(BaseModel):
    title: str | None = Field(default=None, max_length=200)


class AiConversationUpdateIn(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    last_job_id: str | None = None


class AiMessageCreateIn(BaseModel):
    role: str = Field(default="user")  # "user" | "assistant"
    text: str | None = None
    model_url: str | None = None
    job_id: str | None = None
    meta: dict = Field(default_factory=dict)
