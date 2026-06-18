from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import desc, func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_admin
from app.api.routers.freelance import _profile_out
from app.api.schemas.admin import (
    AdminActionIn,
    AdminAssetOut,
    AdminAssetRestoreIn,
    AdminAssetsOut,
    AdminFreelancersOut,
    AdminJobsOut,
    AdminMarketplaceOut,
    AdminModerationOut,
    AdminSummaryOut,
    AdminSystemOut,
    AdminUsersOut,
)
from app.core.config import settings
from app.core.errors import bad_request, not_found
from app.services.system_health import collect_system_health
from app.db.models.freelance import FreelancerApplication
from app.db.models.jobs import AIJob, ScanJob
from app.db.models.marketplace import Asset, Download, Purchase
from app.db.models.report import Report
from app.db.models.user import User, UserProfile
from app.services.audit import log_action

router = APIRouter()

# Soft-moderation visibility state for assets removed by an admin. It is a plain
# value of the existing ``visibility`` string column (no migration needed) and is
# excluded from the public marketplace listing (which only shows "published").
ASSET_REMOVED = "removed"
PUBLIC_VISIBILITIES = ("draft", "published")


def _count(db: Session, stmt) -> int:
    return int(db.execute(stmt).scalar_one() or 0)


def _start_of_today() -> dt.datetime:
    now = dt.datetime.now(dt.timezone.utc)
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


@router.get("/summary", response_model=AdminSummaryOut)
def admin_summary(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    recent_assets = db.execute(
        select(Asset).order_by(desc(Asset.created_at)).limit(6)
    ).scalars().all()

    def _app_count(status: str) -> int:
        return _count(
            db,
            select(func.count())
            .select_from(FreelancerApplication)
            .where(FreelancerApplication.status == status),
        )

    return {
        "users": _count(db, select(func.count()).select_from(User)),
        "active_users": _count(
            db, select(func.count()).select_from(User).where(User.is_active.is_(True))
        ),
        "banned_users": _count(
            db, select(func.count()).select_from(User).where(User.is_active.is_(False))
        ),
        "freelancers": _count(
            db, select(func.count()).select_from(User).where(User.role == "freelancer")
        ),
        "pending_applications": _app_count("pending"),
        "approved_applications": _app_count("approved"),
        "rejected_applications": _app_count("rejected"),
        "total_reports": _count(db, select(func.count()).select_from(Report)),
        "pending_reports": _count(
            db, select(func.count()).select_from(Report).where(Report.status == "pending")
        ),
        "resolved_reports": _count(
            db, select(func.count()).select_from(Report).where(Report.status == "resolved")
        ),
        "failed_ai_jobs": _count(
            db,
            select(func.count())
            .select_from(AIJob)
            .where(AIJob.status.in_(["failed", "error"])),
        ),
        "assets": _count(db, select(func.count()).select_from(Asset)),
        "published_assets": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "published")
        ),
        "draft_assets": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "draft")
        ),
        "downloads": _count(db, select(func.count()).select_from(Download)),
        "purchases": _count(db, select(func.count()).select_from(Purchase)),
        "ai_jobs": _count(db, select(func.count()).select_from(AIJob)),
        "scan_jobs": _count(db, select(func.count()).select_from(ScanJob)),
        "recent_assets": [
            {
                "id": str(asset.id),
                "title": asset.title,
                "creator_id": str(asset.creator_id),
                "visibility": asset.visibility,
                "is_paid": asset.is_paid,
                "price": asset.price,
                "created_at": asset.created_at.isoformat(),
            }
            for asset in recent_assets
        ],
    }


@router.get("/users", response_model=AdminUsersOut)
def admin_users(
    q: str | None = Query(default=None, description="Search by email or username"),
    role: str | None = Query(default=None, description="Filter by role"),
    status: str | None = Query(default=None, description="active | banned"),
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    # The headline counts stay global; the returned list reflects the filters so
    # admins can search/filter the directory without losing the summary numbers.
    stmt = (
        select(User, UserProfile)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .order_by(desc(User.created_at))
    )
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(User.email.ilike(like), UserProfile.username.ilike(like)))
    if role:
        stmt = stmt.where(User.role == role.strip())
    if status == "active":
        stmt = stmt.where(User.is_active.is_(True))
    elif status == "banned":
        stmt = stmt.where(User.is_active.is_(False))
    rows = db.execute(stmt.limit(200)).all()

    creators = _count(
        db, select(func.count(func.distinct(Asset.creator_id))).select_from(Asset)
    )

    return {
        "total": _count(db, select(func.count()).select_from(User)),
        "active": _count(
            db, select(func.count()).select_from(User).where(User.is_active.is_(True))
        ),
        "creators": creators,
        "freelancers": _count(
            db, select(func.count()).select_from(User).where(User.role == "freelancer")
        ),
        "admins": _count(
            db,
            select(func.count())
            .select_from(User)
            .where(User.role.in_(["admin", "super_admin"])),
        ),
        "super_admins": _count(
            db, select(func.count()).select_from(User).where(User.role == "super_admin")
        ),
        "suspended": _count(
            db, select(func.count()).select_from(User).where(User.is_active.is_(False))
        ),
        "users": [
            {
                "id": str(user.id),
                "email": user.email,
                "username": profile.username if profile else None,
                "role": user.role,
                "is_active": user.is_active,
                "created_at": user.created_at.isoformat(),
            }
            for user, profile in rows
        ],
    }


@router.get("/marketplace", response_model=AdminMarketplaceOut)
def admin_marketplace(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    today = _start_of_today()
    assets = db.execute(
        select(Asset).order_by(desc(Asset.created_at)).limit(50)
    ).scalars().all()

    return {
        "total_assets": _count(db, select(func.count()).select_from(Asset)),
        "published": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "published")
        ),
        "draft": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "draft")
        ),
        # No dedicated review queue exists yet; drafts are the items awaiting publish.
        "pending_review": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "draft")
        ),
        # No moderation/flag column exists in the schema yet.
        "flagged": 0,
        "approved_today": _count(
            db,
            select(func.count())
            .select_from(Asset)
            .where(Asset.visibility == "published", Asset.published_at >= today),
        ),
        "downloads": _count(db, select(func.count()).select_from(Download)),
        "purchases": _count(db, select(func.count()).select_from(Purchase)),
        "assets": [
            {
                "id": str(asset.id),
                "title": asset.title,
                "creator_id": str(asset.creator_id),
                "category": asset.category,
                "style": asset.style,
                "visibility": asset.visibility,
                "is_paid": asset.is_paid,
                "price": asset.price,
                "currency": asset.currency,
                "created_at": asset.created_at.isoformat(),
            }
            for asset in assets
        ],
    }


@router.get("/moderation", response_model=AdminModerationOut)
def admin_moderation(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    # Real report-backed signals. Appeals/violations are not modelled yet, so
    # those stay as honest empty collections.
    flagged_users = _count(
        db, select(func.count()).select_from(User).where(User.is_active.is_(False))
    )
    open_reports = _count(
        db, select(func.count()).select_from(Report).where(Report.status == "pending")
    )
    flagged_assets = _count(
        db,
        select(func.count())
        .select_from(Report)
        .where(Report.status == "pending", Report.target_type.in_(["asset", "model"])),
    )
    recent = db.execute(
        select(Report).order_by(desc(Report.created_at)).limit(20)
    ).scalars().all()

    def _reporter_name(reporter_id) -> str | None:
        return db.execute(
            select(UserProfile.username).where(UserProfile.user_id == reporter_id)
        ).scalar_one_or_none()

    return {
        "open_reports": open_reports,
        "appeals": 0,
        "flagged_users": flagged_users,
        "flagged_assets": flagged_assets,
        "reports": [
            {
                "id": str(r.id),
                "reporter_id": str(r.reporter_id),
                "reporter_username": _reporter_name(r.reporter_id),
                "target_type": r.target_type,
                "target_id": r.target_id,
                "reason": r.reason,
                "description": r.description,
                "status": r.status,
                "created_at": r.created_at.isoformat(),
            }
            for r in recent
        ],
        "violations": [],
    }


@router.get("/freelancers", response_model=AdminFreelancersOut)
def admin_freelancers(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    rows = db.execute(
        select(User, UserProfile)
        .join(UserProfile, UserProfile.user_id == User.id)
        .where(User.role == "freelancer")
        .order_by(UserProfile.username)
    ).all()
    profiles = [_profile_out(user, profile) for user, profile in rows]

    return {
        "total": len(profiles),
        "active": _count(
            db,
            select(func.count())
            .select_from(User)
            .where(User.role == "freelancer", User.is_active.is_(True)),
        ),
        "featured": sum(1 for profile in profiles if profile.featured),
        "freelancers": [profile.model_dump() for profile in profiles],
    }


@router.get("/system", response_model=AdminSystemOut)
def admin_system(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    queued = _count(
        db,
        select(func.count())
        .select_from(AIJob)
        .where(AIJob.status.in_(["queued", "processing"])),
    ) + _count(
        db,
        select(func.count())
        .select_from(ScanJob)
        .where(ScanJob.status.in_(["created", "queued", "processing"])),
    )

    # Live, read-only health probes (DB/Redis/Celery/storage/AI/moderation).
    health = collect_system_health(db)

    ai = health.get("ai_pipeline", {})
    modal_status = (ai.get("modal_endpoint") or {}).get("status", "unknown")
    engine_status = (ai.get("stable_diffusion") or {}).get("status", "unknown")
    # GPU/AI line reflects real reachability when configured.
    if modal_status == "reachable":
        gpu_status = "connected"
    elif modal_status == "unreachable":
        gpu_status = "degraded"
    elif modal_status == "not_configured":
        gpu_status = "not_configured"
    else:
        gpu_status = engine_status

    storage_label = (health.get("storage") or {}).get("used_label")
    moderation_status = (health.get("marketplace_moderation") or {}).get(
        "status", "not_configured"
    )

    return {
        # Legacy flat fields (kept for backward compatibility with existing UI):
        "backend": "connected",
        "env": settings.env,
        "gpu_status": gpu_status,
        "queue_size": queued,
        "storage_used": storage_label,
        "pipelines": [
            {"name": "Stable Diffusion image generation", "status": engine_status},
            {"name": "Hunyuan3D mesh generation", "status": engine_status},
            {"name": "Gemini multi-view generation", "status": engine_status},
            {"name": "Marketplace moderation", "status": moderation_status},
        ],
        # Rich live payload consumed by the upgraded System Health UI:
        "health": health,
    }


@router.get("/jobs", response_model=AdminJobsOut)
def admin_jobs(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    ai_recent = db.execute(
        select(AIJob).order_by(desc(AIJob.created_at)).limit(10)
    ).scalars().all()
    scan_recent = db.execute(
        select(ScanJob).order_by(desc(ScanJob.created_at)).limit(10)
    ).scalars().all()

    recent = [
        {
            "id": str(job.id),
            "type": "ai",
            "status": job.status,
            "progress": job.progress,
            "created_at": job.created_at.isoformat(),
        }
        for job in ai_recent
    ] + [
        {
            "id": str(job.id),
            "type": "scan",
            "status": job.status,
            "progress": job.progress,
            "created_at": job.created_at.isoformat(),
        }
        for job in scan_recent
    ]
    recent.sort(key=lambda item: item["created_at"], reverse=True)
    recent = recent[:12]

    def _count_status(model, statuses):
        return _count(
            db,
            select(func.count()).select_from(model).where(model.status.in_(statuses)),
        )

    queue = _count_status(AIJob, ["queued"]) + _count_status(
        ScanJob, ["created", "queued"]
    )
    processing = _count_status(AIJob, ["processing"]) + _count_status(
        ScanJob, ["processing"]
    )
    failed = _count_status(AIJob, ["failed", "error"]) + _count_status(
        ScanJob, ["failed", "error"]
    )
    completed = _count_status(AIJob, ["completed", "done"]) + _count_status(
        ScanJob, ["completed", "done"]
    )

    avg = recent and int(sum(item["progress"] for item in recent) / len(recent)) or 0

    return {
        "queue": queue,
        "processing": processing,
        "failed": failed,
        "completed": completed,
        "ai_jobs": _count(db, select(func.count()).select_from(AIJob)),
        "scan_jobs": _count(db, select(func.count()).select_from(ScanJob)),
        "average_progress": avg,
        "recent": recent,
    }


# --------------------------------------------------------------------------- #
# Asset / marketplace moderation (admin + super_admin)
#
# Admins moderate ANY creator's asset here. Normal users keep managing only
# their own assets via /marketplace/*. Soft-removal uses the existing
# ``visibility`` column plus a ``moderation`` block in ``metadata`` so that a
# restore can return the asset to its previous state — no schema migration.
# --------------------------------------------------------------------------- #


def _load_asset(db: Session, asset_id: str) -> Asset:
    try:
        aid = uuid.UUID(asset_id)
    except (ValueError, TypeError):
        bad_request("Invalid asset id")
    asset = db.get(Asset, aid)
    if not asset:
        not_found("Asset not found")
    return asset


def _creator_username(db: Session, creator_id) -> str | None:
    return db.execute(
        select(UserProfile.username).where(UserProfile.user_id == creator_id)
    ).scalar_one_or_none()


def _asset_admin_out(asset: Asset, username: str | None) -> dict:
    mod = (asset.meta_json or {}).get("moderation") or {}
    return {
        "id": str(asset.id),
        "title": asset.title,
        "creator_id": str(asset.creator_id),
        "creator_username": username,
        "category": asset.category,
        "style": asset.style,
        "visibility": asset.visibility,
        "is_paid": asset.is_paid,
        "price": asset.price,
        "currency": asset.currency,
        "moderation_status": mod.get("status"),
        "moderation_reason": mod.get("reason"),
        "created_at": asset.created_at.isoformat(),
    }


@router.get("/assets", response_model=AdminAssetsOut)
def admin_assets(
    q: str | None = Query(default=None, description="Search by title/description"),
    visibility: str | None = Query(
        default=None, description="draft | published | removed"
    ),
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    stmt = select(Asset)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Asset.title.ilike(like), Asset.description.ilike(like)))
    if visibility in (*PUBLIC_VISIBILITIES, ASSET_REMOVED):
        stmt = stmt.where(Asset.visibility == visibility)
    rows = db.execute(stmt.order_by(desc(Asset.created_at)).limit(200)).scalars().all()

    creator_ids = {a.creator_id for a in rows}
    names: dict = {}
    if creator_ids:
        prows = db.execute(
            select(UserProfile).where(UserProfile.user_id.in_(creator_ids))
        ).scalars().all()
        names = {p.user_id: p.username for p in prows}

    return {
        "total": _count(db, select(func.count()).select_from(Asset)),
        "published": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "published")
        ),
        "draft": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == "draft")
        ),
        "removed": _count(
            db, select(func.count()).select_from(Asset).where(Asset.visibility == ASSET_REMOVED)
        ),
        "assets": [_asset_admin_out(a, names.get(a.creator_id)) for a in rows],
    }


@router.post("/assets/{asset_id}/hide", response_model=AdminAssetOut)
def admin_hide_asset(
    asset_id: str,
    payload: AdminActionIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    asset = _load_asset(db, asset_id)
    if asset.visibility == ASSET_REMOVED:
        bad_request("Asset is already removed")
    previous = asset.visibility
    reason = payload.reason if payload else None
    meta = dict(asset.meta_json or {})
    meta["moderation"] = {
        "status": ASSET_REMOVED,
        "previous_visibility": previous,
        "reason": reason,
        "by": str(actor.id),
        "at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    asset.meta_json = meta
    asset.visibility = ASSET_REMOVED
    log_action(
        db,
        actor_id=actor.id,
        action="asset.hide",
        entity="asset",
        entity_id=str(asset.id),
        meta={"old": previous, "new": ASSET_REMOVED, "reason": reason},
    )
    db.commit()
    db.refresh(asset)
    return _asset_admin_out(asset, _creator_username(db, asset.creator_id))


@router.post("/assets/{asset_id}/restore", response_model=AdminAssetOut)
def admin_restore_asset(
    asset_id: str,
    payload: AdminAssetRestoreIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    asset = _load_asset(db, asset_id)
    meta = dict(asset.meta_json or {})
    mod = meta.get("moderation") or {}
    target = (payload.visibility if payload and payload.visibility else None) or mod.get(
        "previous_visibility"
    ) or "draft"
    if target not in PUBLIC_VISIBILITIES:
        target = "draft"
    previous = asset.visibility
    meta.pop("moderation", None)
    asset.meta_json = meta
    asset.visibility = target
    if target == "published" and not asset.published_at:
        asset.published_at = dt.datetime.now(dt.timezone.utc)
    log_action(
        db,
        actor_id=actor.id,
        action="asset.restore",
        entity="asset",
        entity_id=str(asset.id),
        meta={"old": previous, "new": target},
    )
    db.commit()
    db.refresh(asset)
    return _asset_admin_out(asset, _creator_username(db, asset.creator_id))


@router.delete("/assets/{asset_id}")
def admin_delete_asset(
    asset_id: str,
    payload: AdminActionIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    asset = _load_asset(db, asset_id)
    log_action(
        db,
        actor_id=actor.id,
        action="asset.delete",
        entity="asset",
        entity_id=str(asset.id),
        meta={
            "title": asset.title,
            "creator_id": str(asset.creator_id),
            "reason": payload.reason if payload else None,
        },
    )
    db.delete(asset)
    db.commit()
    return {"detail": "ok"}
