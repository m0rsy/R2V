from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Any

class Page(BaseModel):
    items: list[Any]
    total: int
    limit: int
    offset: int

class Message(BaseModel):
    detail: str

class PresignedURL(BaseModel):
    url: str
    method: str = "PUT"
    headers: dict[str, str] = Field(default_factory=dict)

class PresignIn(BaseModel):
    filename: str
    content_type: str = "application/octet-stream"
