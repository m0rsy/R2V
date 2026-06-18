from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_permission
from app.api.schemas.freelance import AdminRejectIn, StatusPatchIn
from app.core.errors import bad_request, not_found
from app.core.permissions import ROLE_FREELANCER
from app.db.models.freelance import FreelancerApplication
from app.db.models.freelance_market import (
    FreelanceOrder,
    FreelanceReview,
    FreelanceService,
    FreelancerProfile,
)
from app.db.models.user import User
from app.services import freelance as fl
from app.services.audit import log_action

router = APIRouter()


def _uuid(value: str, label: str = "id") -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError):
        bad_request(f"Invalid {label}")


def _get_application(db: Session, application_id: str) -> FreelancerApplication:
    app = db.get(FreelancerApplication, _uuid(application_id, "application id"))
    if not app:
        not_found("Application not found")
    return app


def _get_profile(db: Session, profile_id: str) -> FreelancerProfile:
    profile = db.get(FreelancerProfile, _uuid(profile_id, "freelancer id"))
    if not profile:
        not_found("Freelancer not found")
    return profile


def _get_service(db: Session, service_id: str) -> FreelanceService:
    service = db.get(FreelanceService, _uuid(service_id, "service id"))
    if not service:
        not_found("Service not found")
    return service


@router.get("/freelance/applications")
def applications(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_freelancers")),
    status: str | None = Query(default=None),
):
    stmt = select(FreelancerApplication)
    if status and status != "all":
        normalized = fl.validate_application_status(status)
        stmt = stmt.where(FreelancerApplication.status == normalized)
    rows = db.execute(stmt.order_by(desc(FreelancerApplication.created_at)).limit(200)).scalars().all()
    return {
        "total": len(rows),
        "applications": [fl.serialize_application(db, app) for app in rows],
    }


@router.patch("/freelance/applications/{application_id}/approve")
def approve_application(
    application_id: str,
    payload: AdminRejectIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("approve_freelancers")),
):
    app = _get_application(db, application_id)
    user = db.get(User, app.user_id)
    if not user:
        not_found("Applicant not found")
    user.role = ROLE_FREELANCER
    app.status = "approved"
    app.admin_note = payload.admin_note if payload else app.admin_note
    app.reviewed_by = actor.id
    app.reviewed_at = fl.utcnow()
    profile = db.execute(
        select(FreelancerProfile).where(FreelancerProfile.user_id == app.user_id)
    ).scalar_one_or_none()
    if profile is None:
        profile = FreelancerProfile(
            user_id=app.user_id,
            display_name=app.full_name,
            title=app.title,
            bio=app.experience,
            skills=app.skills,
            categories=[],
            portfolio_links=app.portfolio_links,
            starting_price=None,
            status="approved",
        )
        db.add(profile)
    else:
        profile.display_name = app.full_name
        profile.title = app.title
        # Only seed bio from the application when the freelancer has not set one,
        # so re-approving never clobbers a profile the freelancer edited.
        if not profile.bio:
            profile.bio = app.experience
        profile.skills = app.skills
        profile.portfolio_links = app.portfolio_links
        profile.status = "approved"
    log_action(
        db,
        actor_id=actor.id,
        action="freelance.application.approve",
        entity="freelancer_application",
        entity_id=str(app.id),
        meta={"user_id": str(app.user_id)},
    )
    db.commit()
    db.refresh(app)
    return fl.serialize_application(db, app)


@router.patch("/freelance/applications/{application_id}/reject")
def reject_application(
    application_id: str,
    payload: AdminRejectIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("reject_freelancers")),
):
    app = _get_application(db, application_id)
    app.status = "rejected"
    app.admin_note = payload.admin_note or payload.reason
    app.reviewed_by = actor.id
    app.reviewed_at = fl.utcnow()
    log_action(
        db,
        actor_id=actor.id,
        action="freelance.application.reject",
        entity="freelancer_application",
        entity_id=str(app.id),
        meta={"user_id": str(app.user_id)},
    )
    db.commit()
    db.refresh(app)
    return fl.serialize_application(db, app)


@router.patch("/freelance/applications/{application_id}/request-info")
def request_more_info(
    application_id: str,
    payload: AdminRejectIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("approve_freelancers")),
):
    app = _get_application(db, application_id)
    app.status = "needs_more_info"
    if payload:
        app.admin_note = payload.admin_note or payload.reason or app.admin_note
    app.reviewed_by = actor.id
    app.reviewed_at = fl.utcnow()
    log_action(
        db,
        actor_id=actor.id,
        action="freelance.application.request_info",
        entity="freelancer_application",
        entity_id=str(app.id),
        meta={"user_id": str(app.user_id)},
    )
    db.commit()
    db.refresh(app)
    return fl.serialize_application(db, app)


@router.get("/freelance/freelancers")
def freelancers(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_freelancers")),
    status: str | None = Query(default=None),
):
    stmt = select(FreelancerProfile)
    if status:
        stmt = stmt.where(FreelancerProfile.status == status)
    rows = db.execute(stmt.order_by(desc(FreelancerProfile.created_at)).limit(200)).scalars().all()
    return [fl.serialize_profile(db, profile) for profile in rows]


@router.patch("/freelance/freelancers/{freelancer_id}/status")
def freelancer_status(
    freelancer_id: str,
    payload: StatusPatchIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("approve_freelancers")),
):
    profile = _get_profile(db, freelancer_id)
    profile.status = fl.validate_profile_status(payload.status)
    log_action(
        db,
        actor_id=actor.id,
        action="freelance.freelancer.status",
        entity="freelancer_profile",
        entity_id=str(profile.id),
        meta={"status": profile.status},
    )
    db.commit()
    return fl.serialize_profile(db, profile)


@router.get("/freelance/orders")
def orders(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_orders")),
    status: str | None = Query(default=None),
):
    stmt = select(FreelanceOrder)
    if status:
        stmt = stmt.where(FreelanceOrder.status == status)
    rows = db.execute(stmt.order_by(desc(FreelanceOrder.created_at)).limit(300)).scalars().all()
    return [fl.serialize_order(db, order, actor) for order in rows]


@router.get("/freelance/services")
def services(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_freelancers")),
    status: str | None = Query(default=None),
):
    stmt = select(FreelanceService)
    if status:
        stmt = stmt.where(FreelanceService.status == status)
    rows = db.execute(stmt.order_by(desc(FreelanceService.created_at)).limit(300)).scalars().all()
    return [fl.serialize_service(db, service) for service in rows]


@router.patch("/freelance/services/{service_id}/status")
def service_status(
    service_id: str,
    payload: StatusPatchIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("manage_orders")),
):
    service = _get_service(db, service_id)
    service.status = fl.validate_service_status(payload.status)
    log_action(
        db,
        actor_id=actor.id,
        action="freelance.service.status",
        entity="freelance_service",
        entity_id=str(service.id),
        meta={"status": service.status},
    )
    db.commit()
    return fl.serialize_service(db, service)


@router.get("/freelance/disputes")
def disputes(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_reports")),
):
    rows = db.execute(
        select(FreelanceOrder)
        .where(FreelanceOrder.status == "disputed")
        .order_by(desc(FreelanceOrder.updated_at))
        .limit(200)
    ).scalars().all()
    return [fl.serialize_order(db, order, actor) for order in rows]


@router.get("/freelance/reports")
def reports(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_analytics")),
):
    totals_by_status = dict(
        db.execute(select(FreelanceOrder.status, func.count(FreelanceOrder.id)).group_by(FreelanceOrder.status)).all()
    )
    revenue = db.execute(
        select(func.coalesce(func.sum(FreelanceOrder.budget), 0)).where(FreelanceOrder.status == "completed")
    ).scalar_one()
    reviews = db.execute(select(func.count(FreelanceReview.id))).scalar_one()
    return {
        "applications": db.execute(select(func.count(FreelancerApplication.id))).scalar_one(),
        "freelancers": db.execute(select(func.count(FreelancerProfile.id))).scalar_one(),
        "services": db.execute(select(func.count(FreelanceService.id))).scalar_one(),
        "orders": db.execute(select(func.count(FreelanceOrder.id))).scalar_one(),
        "orders_by_status": {str(k): int(v) for k, v in totals_by_status.items()},
        "disputes": int(totals_by_status.get("disputed", 0)),
        "reviews": int(reviews or 0),
        "completed_revenue": float(revenue or 0),
    }


@router.get("/freelance/summary")
def summary(
    db: Session = Depends(get_db),
    actor: User = Depends(require_permission("view_analytics")),
):
    return reports(db, actor)
