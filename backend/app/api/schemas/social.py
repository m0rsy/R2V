from __future__ import annotations
from pydantic import BaseModel, Field

class ProfileOut(BaseModel):
    user_id: str
    username: str
    bio: str | None = None
    avatar_url: str | None = None
    posts: int
    followers: int
    following: int
    is_following: bool = False
    is_followed_by: bool = False
    # True only when both users follow each other (direct messaging is allowed).
    is_mutual: bool = False
    is_self: bool = False

class FollowUserOut(BaseModel):
    user_id: str
    username: str
    avatar_url: str | None = None

class PostCreateIn(BaseModel):
    asset_id: str | None = None
    caption: str | None = None
    media_keys: list[str] = Field(default_factory=list)

class PostOut(BaseModel):
    id: str
    creator_id: str
    asset_id: str | None = None
    caption: str | None = None
    media_keys: list[str] = Field(default_factory=list)
    created_at: str
