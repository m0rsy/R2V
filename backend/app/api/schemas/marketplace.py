from __future__ import annotations
from pydantic import BaseModel, Field
from typing import Any

class AssetOut(BaseModel):
    id: str
    title: str
    description: str | None = None
    tags: list[str] = Field(default_factory=list)
    category: str
    style: str
    creator_id: str
    is_paid: bool
    price: int
    currency: str
    visibility: str
    published_at: str | None = None
    thumb_object_key: str | None = None
    thumb_url: str | None = None
    model_object_key: str
    preview_url: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    # Per-user state for the current request (false for anonymous callers).
    liked_by_me: bool = False
    saved_by_me: bool = False
    # Aggregate like count (also mirrored in metadata["likes"] for back-compat).
    likes_count: int = 0

class AssetCreateIn(BaseModel):
    title: str
    description: str | None = None
    tags: list[str] = Field(default_factory=list)
    category: str
    style: str
    is_paid: bool = False
    price: int = 0
    currency: str = "usd"
    license: str | None = None
    model_object_key: str
    thumb_object_key: str | None = None
    preview_object_keys: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)

class AssetUpdateIn(BaseModel):
    title: str | None = None
    description: str | None = None
    tags: list[str] | None = None
    category: str | None = None
    style: str | None = None
    is_paid: bool | None = None
    price: int | None = None
    currency: str | None = None
    license: str | None = None
    thumb_object_key: str | None = None
    preview_object_keys: list[str] | None = None
    metadata: dict[str, Any] | None = None

class AssetPresignIn(BaseModel):
    filename: str
    content_type: str = "application/octet-stream"
    kind: str = "model"

class AssetPresignOut(BaseModel):
    url: str
    key: str

class EntitlementOut(BaseModel):
    asset_id: str
    entitled: bool
    reason: str
