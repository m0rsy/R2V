from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

VALID_TARGET_TYPES = {"asset", "model", "freelancer", "user", "order", "other"}


class ReportCreateIn(BaseModel):
    target_type: str = Field(min_length=1, max_length=32)
    target_id: str = Field(min_length=1, max_length=64)
    reason: str = Field(min_length=1, max_length=64)
    description: str | None = Field(default=None, max_length=2000)


class ReportOut(BaseModel):
    id: str
    reporter_id: str
    reporter_username: str | None = None
    target_type: str
    target_id: str
    reason: str
    description: str | None = None
    status: str
    admin_note: str | None = None
    created_at: str
    resolved_at: str | None = None


class ReportReviewIn(BaseModel):
    admin_note: str | None = Field(default=None, max_length=2000)


class AdminReportsOut(BaseModel):
    total: int
    pending: int
    resolved: int
    rejected: int
    reports: list[dict[str, Any]]
