from __future__ import annotations

from typing import Any

from pydantic import BaseModel, EmailStr, Field


class AdminSummaryOut(BaseModel):
    users: int
    active_users: int
    banned_users: int = 0
    freelancers: int = 0
    pending_applications: int = 0
    approved_applications: int = 0
    rejected_applications: int = 0
    total_reports: int = 0
    pending_reports: int = 0
    resolved_reports: int = 0
    assets: int
    published_assets: int
    draft_assets: int
    downloads: int
    purchases: int
    ai_jobs: int
    failed_ai_jobs: int = 0
    scan_jobs: int
    recent_assets: list[dict[str, Any]]


class AdminUsersOut(BaseModel):
    total: int
    active: int
    creators: int
    freelancers: int
    admins: int
    super_admins: int = 0
    suspended: int
    users: list[dict[str, Any]]


class AdminMarketplaceOut(BaseModel):
    total_assets: int
    published: int
    draft: int
    pending_review: int
    flagged: int
    approved_today: int
    downloads: int
    purchases: int
    assets: list[dict[str, Any]]


class AdminModerationOut(BaseModel):
    open_reports: int
    appeals: int
    flagged_users: int
    flagged_assets: int
    reports: list[dict[str, Any]]
    violations: list[dict[str, Any]]


class AdminFreelancersOut(BaseModel):
    total: int
    active: int
    featured: int
    freelancers: list[dict[str, Any]]


class AdminPipelineStatus(BaseModel):
    name: str
    status: str


class AdminSystemOut(BaseModel):
    backend: str
    env: str
    gpu_status: str
    queue_size: int
    storage_used: str | None
    pipelines: list[AdminPipelineStatus]
    # Rich live health payload (backend/database/redis/celery/storage/
    # ai_pipeline/marketplace_moderation/warnings). Kept as a free-form dict so
    # the response can evolve without brittle nested schemas; contains only
    # statuses/latencies/counts/booleans — never secrets.
    health: dict[str, Any] = Field(default_factory=dict)


class AdminJobsOut(BaseModel):
    queue: int
    processing: int
    failed: int
    completed: int
    ai_jobs: int
    scan_jobs: int
    average_progress: int
    recent: list[dict[str, Any]]


# --------------------------------------------------------------------------- #
# Admins management (super_admin only)
# --------------------------------------------------------------------------- #


class AdminAccountOut(BaseModel):
    id: str
    email: str
    username: str | None = None
    role: str
    is_active: bool
    created_at: str


class AdminAccountsOut(BaseModel):
    total: int
    admins: int
    super_admins: int
    accounts: list[AdminAccountOut]


class CreateAdminIn(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=8, max_length=128)


class RoleTargetIn(BaseModel):
    user_id: str


class RoleUpdateIn(BaseModel):
    role: str


# Alias kept for clarity at the call sites that change a user's role.
AdminRoleUpdateIn = RoleUpdateIn


class AdminActionIn(BaseModel):
    """Generic moderation action payload (ban / hide / delete). All optional so
    the action can be invoked with an empty body."""

    reason: str | None = Field(default=None, max_length=500)


# --------------------------------------------------------------------------- #
# Asset moderation (admin + super_admin)
# --------------------------------------------------------------------------- #


class AdminAssetOut(BaseModel):
    id: str
    title: str
    creator_id: str
    creator_username: str | None = None
    category: str
    style: str
    visibility: str
    is_paid: bool
    price: int
    currency: str
    moderation_status: str | None = None
    moderation_reason: str | None = None
    created_at: str


class AdminAssetsOut(BaseModel):
    total: int
    published: int
    draft: int
    removed: int
    assets: list[AdminAssetOut]


class AdminAssetRestoreIn(BaseModel):
    # Optional explicit target visibility; otherwise the pre-removal visibility
    # (or "draft") is restored.
    visibility: str | None = None


# --------------------------------------------------------------------------- #
# Freelancer applications (admin review)
# --------------------------------------------------------------------------- #


class AdminApplicationReviewIn(BaseModel):
    admin_note: str | None = Field(default=None, max_length=2000)


class AdminApplicationsOut(BaseModel):
    total: int
    pending: int
    approved: int
    rejected: int
    applications: list[dict[str, Any]]
