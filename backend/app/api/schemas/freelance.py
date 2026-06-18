from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, Field, field_validator

from app.db.models.freelance_market import (
    AVAILABILITY_STATUSES,
    FREELANCE_CATEGORIES,
    ORDER_STATUSES,
    SERVICE_STATUSES,
)


def _clean(values: list[str] | None, limit: int = 40) -> list[str]:
    out: list[str] = []
    for value in values or []:
        item = str(value).strip()
        if item and item not in out:
            out.append(item)
        if len(out) >= limit:
            break
    return out


class FreelancerApplicationIn(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=140)
    display_name: str | None = Field(default=None, min_length=2, max_length=140)
    title: str = Field(min_length=2, max_length=140)
    skills: list[str] = Field(default_factory=list)
    experience: str | None = Field(default=None, max_length=6000)
    portfolio_links: list[str] = Field(default_factory=list)
    portfolio_url: str | None = Field(default=None, max_length=600)
    expected_price_range: str | None = Field(default=None, max_length=120)
    message: str | None = Field(default=None, max_length=4000)

    @field_validator("skills", "portfolio_links")
    @classmethod
    def _clean_list(cls, value: list[str]) -> list[str]:
        return _clean(value)


class FreelancerApplicationOut(BaseModel):
    id: str
    user_id: str
    email: str | None = None
    username: str | None = None
    avatar_url: str | None = None
    full_name: str
    display_name: str
    title: str
    skills: list[str] = Field(default_factory=list)
    experience: str | None = None
    portfolio_links: list[str] = Field(default_factory=list)
    expected_price_range: str | None = None
    message: str | None = None
    status: str
    admin_note: str | None = None
    reviewed_at: str | None = None
    created_at: str | None = None
    updated_at: str | None = None


class FreelancerProfileIn(BaseModel):
    display_name: str | None = Field(default=None, min_length=2, max_length=140)
    title: str | None = Field(default=None, min_length=2, max_length=140)
    bio: str | None = Field(default=None, max_length=5000)
    skills: list[str] | None = None
    categories: list[str] | None = None
    hourly_rate: float | None = Field(default=None, ge=0, le=1_000_000)
    starting_price: float | None = Field(default=None, ge=0, le=1_000_000)
    profile_image: str | None = Field(default=None, max_length=1000)
    portfolio_links: list[str] | None = None
    availability: str | None = None

    @field_validator("skills", "categories", "portfolio_links")
    @classmethod
    def _clean_list(cls, value: list[str] | None) -> list[str] | None:
        return None if value is None else _clean(value)

    @field_validator("availability")
    @classmethod
    def _availability(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if value not in AVAILABILITY_STATUSES:
            raise ValueError("Invalid availability")
        return value


class FreelancerProfileOut(BaseModel):
    id: str
    user_id: str
    username: str | None = None
    email: str | None = None
    display_name: str
    title: str
    role: str | None = None
    bio: str | None = None
    skills: list[str] = Field(default_factory=list)
    categories: list[str] = Field(default_factory=list)
    category: str | None = None
    hourly_rate: float | None = None
    starting_price: float | None = None
    profile_image: str | None = None
    avatar_url: str | None = None
    cover_url: str | None = None
    portfolio_links: list[str] = Field(default_factory=list)
    portfolio: list[str] = Field(default_factory=list)
    status: str
    availability: str
    rating_average: float = 0
    rating_avg: float = 0
    rating: float = 0
    rating_count: int = 0
    reviews: int | list = 0
    reviews_count: int = 0
    completed_jobs_count: int = 0
    completed_jobs: int = 0
    featured: bool = False
    services: list = Field(default_factory=list)
    created_at: str | None = None
    updated_at: str | None = None


FreelanceProfileOut = FreelancerProfileOut


class ServiceIn(BaseModel):
    title: str = Field(min_length=3, max_length=180)
    description: str = Field(min_length=10, max_length=8000)
    category: str
    tags: list[str] = Field(default_factory=list)
    starting_price: float = Field(ge=0, le=10_000_000)
    delivery_days: int = Field(default=7, ge=1, le=365)
    revisions: int = Field(default=1, ge=0, le=50)
    file_formats: list[str] = Field(default_factory=list)
    images: list[str] = Field(default_factory=list)
    status: str = "active"

    @field_validator("category")
    @classmethod
    def _category(cls, value: str) -> str:
        if value not in FREELANCE_CATEGORIES:
            raise ValueError("Invalid freelance category")
        return value

    @field_validator("status")
    @classmethod
    def _status(cls, value: str) -> str:
        if value not in SERVICE_STATUSES:
            raise ValueError("Invalid service status")
        return value

    @field_validator("tags", "file_formats", "images")
    @classmethod
    def _clean_list(cls, value: list[str]) -> list[str]:
        return _clean(value)


class ServiceUpdateIn(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=180)
    description: str | None = Field(default=None, min_length=10, max_length=8000)
    category: str | None = None
    tags: list[str] | None = None
    starting_price: float | None = Field(default=None, ge=0, le=10_000_000)
    delivery_days: int | None = Field(default=None, ge=1, le=365)
    revisions: int | None = Field(default=None, ge=0, le=50)
    file_formats: list[str] | None = None
    images: list[str] | None = None
    status: str | None = None


class OrderCreateIn(BaseModel):
    freelancer_id: str | None = None
    service_id: str | None = None
    title: str = Field(min_length=3, max_length=180)
    requirements: str = Field(min_length=10, max_length=10000)
    budget: float = Field(ge=0, le=10_000_000)
    deadline: dt.datetime | None = None
    attachments: list[str] = Field(default_factory=list)
    category: str | None = None

    @field_validator("attachments")
    @classmethod
    def _attachments(cls, value: list[str]) -> list[str]:
        return _clean(value, limit=80)


class OrderStatusIn(BaseModel):
    status: str
    reason: str | None = Field(default=None, max_length=4000)

    @field_validator("status")
    @classmethod
    def _status(cls, value: str) -> str:
        if value not in ORDER_STATUSES:
            raise ValueError("Invalid order status")
        return value


class DeliveryIn(BaseModel):
    message: str | None = Field(default=None, max_length=4000)
    files: list[str] = Field(default_factory=list)


class RevisionIn(BaseModel):
    note: str = Field(min_length=2, max_length=4000)


class ReviewIn(BaseModel):
    rating: int = Field(ge=1, le=5)
    quality_rating: int = Field(default=5, ge=1, le=5)
    communication_rating: int = Field(default=5, ge=1, le=5)
    delivery_rating: int = Field(default=5, ge=1, le=5)
    comment: str | None = Field(default=None, max_length=4000)


class MessageIn(BaseModel):
    message: str | None = Field(default=None, max_length=8000)
    text: str | None = Field(default=None, max_length=8000)
    attachments: list[str] = Field(default_factory=list)


class AdminRejectIn(BaseModel):
    admin_note: str | None = Field(default=None, max_length=4000)
    reason: str | None = Field(default=None, max_length=4000)


class StatusPatchIn(BaseModel):
    status: str
    admin_note: str | None = Field(default=None, max_length=4000)


class DisputeIn(BaseModel):
    reason: str = Field(min_length=5, max_length=4000)


class ContextOpenIn(BaseModel):
    context_type: str = "order"
    context_id: str


class FreelanceMessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=8000)


class ProjectIn(BaseModel):
    title: str
    description: str


class ProjectUpdateIn(BaseModel):
    title: str | None = None


class ProposalIn(BaseModel):
    cover_letter: str
    price: float


class MilestoneIn(BaseModel):
    title: str


class ReviewOut(BaseModel):
    id: str
    order_id: str
    client_id: str
    reviewer_id: str
    freelancer_id: str
    reviewee_id: str
    rating: int
    quality_rating: int
    communication_rating: int
    delivery_rating: int
    comment: str | None = None
    created_at: str | None = None


ProjectOut = dict
ProposalOut = dict
OrderOut = dict
