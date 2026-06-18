from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_admin, require_super_admin
from app.api.routers.freelance import promote_to_freelancer, serialize_application
from app.api.schemas.admin import (
    AdminAccountOut,
    AdminAccountsOut,
    AdminActionIn,
    AdminApplicationReviewIn,
    AdminApplicationsOut,
    CreateAdminIn,
    RoleTargetIn,
    RoleUpdateIn,
)
from app.api.schemas.freelance import FreelancerApplicationOut
from app.core.errors import bad_request, conflict, forbidden, not_found
from app.core.permissions import (
    ADMIN_ROLES,
    ALL_ROLES,
    ROLE_ADMIN,
    ROLE_SUPER_ADMIN,
    ROLE_USER,
)
from app.core.security import hash_password
from app.db.models.freelance import FreelancerApplication
from app.db.models.user import RefreshToken, User, UserProfile
from app.services.audit import log_action

router = APIRouter()


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def _count(db: Session, stmt) -> int:
    return int(db.execute(stmt).scalar_one() or 0)


def _super_admin_count(db: Session) -> int:
    return _count(
        db,
        select(func.count()).select_from(User).where(User.role == ROLE_SUPER_ADMIN),
    )


def _account_out(user: User, profile: UserProfile | None) -> AdminAccountOut:
    return AdminAccountOut(
        id=str(user.id),
        email=user.email,
        username=profile.username if profile else None,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at.isoformat(),
    )


def _load_target(db: Session, user_id: str) -> User:
    try:
        uid = uuid.UUID(user_id)
    except (ValueError, TypeError):
        bad_request("Invalid user id")
    user = db.get(User, uid)
    if not user:
        not_found("User not found")
    return user


# --------------------------------------------------------------------------- #
# Admins management (super_admin only)
# --------------------------------------------------------------------------- #


@router.get("/admins", response_model=AdminAccountsOut)
def list_admins(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_super_admin),
):
    rows = db.execute(
        select(User, UserProfile)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(User.role.in_([ROLE_ADMIN, ROLE_SUPER_ADMIN]))
        .order_by(desc(User.created_at))
    ).all()
    accounts = [_account_out(user, profile) for user, profile in rows]
    return AdminAccountsOut(
        total=len(accounts),
        admins=sum(1 for a in accounts if a.role == ROLE_ADMIN),
        super_admins=sum(1 for a in accounts if a.role == ROLE_SUPER_ADMIN),
        accounts=accounts,
    )


@router.post("/admins", response_model=AdminAccountOut)
def create_admin(
    payload: CreateAdminIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_super_admin),
):
    email = payload.email.lower().strip()
    if db.execute(select(User).where(User.email == email)).scalar_one_or_none():
        conflict("Email already registered")
    if db.execute(
        select(UserProfile).where(UserProfile.username == payload.username)
    ).scalar_one_or_none():
        conflict("Username already taken")

    user = User(
        email=email,
        password_hash=hash_password(payload.password),
        role=ROLE_ADMIN,
        is_active=True,
    )
    user.profile = UserProfile(username=payload.username, bio=None, avatar_url=None, links=None)
    db.add(user)
    db.flush()
    log_action(
        db,
        actor_id=actor.id,
        action="admin.create",
        entity="user",
        entity_id=str(user.id),
        meta={"email": email, "role": ROLE_ADMIN},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


@router.post("/admins/promote", response_model=AdminAccountOut)
def promote_admin(
    payload: RoleTargetIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_super_admin),
):
    user = _load_target(db, payload.user_id)
    if not user.is_active:
        bad_request("Cannot change the role of an inactive account")
    if user.role in (ROLE_ADMIN, ROLE_SUPER_ADMIN):
        bad_request("User is already an admin")

    previous = user.role
    user.role = ROLE_ADMIN
    log_action(
        db,
        actor_id=actor.id,
        action="admin.promote",
        entity="user",
        entity_id=str(user.id),
        meta={"from": previous, "to": ROLE_ADMIN},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


@router.post("/admins/demote", response_model=AdminAccountOut)
def demote_admin(
    payload: RoleTargetIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_super_admin),
):
    user = _load_target(db, payload.user_id)
    if user.role == ROLE_SUPER_ADMIN:
        bad_request("Super admins cannot be demoted from here")
    if user.role != ROLE_ADMIN:
        bad_request("User is not an admin")

    user.role = ROLE_USER
    log_action(
        db,
        actor_id=actor.id,
        action="admin.demote",
        entity="user",
        entity_id=str(user.id),
        meta={"from": ROLE_ADMIN, "to": ROLE_USER},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


@router.patch("/users/{user_id}/role", response_model=AdminAccountOut)
def change_user_role(
    user_id: str,
    payload: RoleUpdateIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_super_admin),
):
    new_role = payload.role.strip()
    if new_role not in ALL_ROLES:
        bad_request(f"Invalid role. Allowed: {', '.join(ALL_ROLES)}")
    user = _load_target(db, user_id)
    if not user.is_active:
        bad_request("Cannot change the role of an inactive account")

    previous = user.role
    if previous == new_role:
        return _account_out(user, user.profile)

    # Protect the last super admin from losing privileges.
    if previous == ROLE_SUPER_ADMIN and new_role != ROLE_SUPER_ADMIN:
        if _super_admin_count(db) <= 1:
            forbidden("Cannot remove the last super admin")

    user.role = new_role
    log_action(
        db,
        actor_id=actor.id,
        action="admin.change_role",
        entity="user",
        entity_id=str(user.id),
        meta={"from": previous, "to": new_role},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


# --------------------------------------------------------------------------- #
# User moderation: ban / unban (admin + super_admin)
# --------------------------------------------------------------------------- #


@router.post("/users/{user_id}/ban", response_model=AdminAccountOut)
def ban_user(
    user_id: str,
    payload: AdminActionIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    user = _load_target(db, user_id)
    # Guardrails: never ban yourself, never ban a fellow admin/super_admin.
    if user.id == actor.id:
        bad_request("You cannot ban your own account")
    if user.role in ADMIN_ROLES:
        forbidden("Admins cannot be banned. Demote the account first.")
    if not user.is_active:
        bad_request("User is already banned")

    reason = payload.reason if payload else None
    user.is_active = False
    # Revoke active sessions so the ban takes effect immediately even if the user
    # holds a still-valid access token (refresh will now fail).
    db.query(RefreshToken).filter(RefreshToken.user_id == user.id).delete()
    log_action(
        db,
        actor_id=actor.id,
        action="user.ban",
        entity="user",
        entity_id=str(user.id),
        meta={"role": user.role, "reason": reason},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


@router.post("/users/{user_id}/unban", response_model=AdminAccountOut)
def unban_user(
    user_id: str,
    payload: AdminActionIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    user = _load_target(db, user_id)
    if user.is_active:
        bad_request("User is not banned")

    user.is_active = True
    log_action(
        db,
        actor_id=actor.id,
        action="user.unban",
        entity="user",
        entity_id=str(user.id),
        meta={"role": user.role, "reason": payload.reason if payload else None},
    )
    db.commit()
    db.refresh(user)
    return _account_out(user, user.profile)


# --------------------------------------------------------------------------- #
# Freelancer application review (admin + super_admin)
# --------------------------------------------------------------------------- #


@router.get("/freelancer-applications", response_model=AdminApplicationsOut)
def list_applications(
    status: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    stmt = select(FreelancerApplication).order_by(desc(FreelancerApplication.created_at))
    if status in ("pending", "approved", "rejected"):
        stmt = stmt.where(FreelancerApplication.status == status)
    apps = db.execute(stmt.limit(200)).scalars().all()

    def _status_count(value: str) -> int:
        return _count(
            db,
            select(func.count())
            .select_from(FreelancerApplication)
            .where(FreelancerApplication.status == value),
        )

    return AdminApplicationsOut(
        total=_count(db, select(func.count()).select_from(FreelancerApplication)),
        pending=_status_count("pending"),
        approved=_status_count("approved"),
        rejected=_status_count("rejected"),
        applications=[serialize_application(db, app).model_dump() for app in apps],
    )


def _load_application(db: Session, application_id: str) -> FreelancerApplication:
    try:
        aid = uuid.UUID(application_id)
    except (ValueError, TypeError):
        bad_request("Invalid application id")
    app = db.get(FreelancerApplication, aid)
    if not app:
        not_found("Application not found")
    return app


@router.post(
    "/freelancer-applications/{application_id}/approve",
    response_model=FreelancerApplicationOut,
)
def approve_application(
    application_id: str,
    payload: AdminApplicationReviewIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    app = _load_application(db, application_id)
    if app.status != "pending":
        bad_request(f"Application already {app.status}")

    promote_to_freelancer(db, app)
    app.status = "approved"
    app.admin_note = payload.admin_note if payload else None
    app.reviewed_by = actor.id
    app.reviewed_at = dt.datetime.now(dt.timezone.utc)
    log_action(
        db,
        actor_id=actor.id,
        action="freelancer.approve",
        entity="freelancer_application",
        entity_id=str(app.id),
        meta={"user_id": str(app.user_id)},
    )
    db.commit()
    db.refresh(app)
    return serialize_application(db, app)


@router.post(
    "/freelancer-applications/{application_id}/reject",
    response_model=FreelancerApplicationOut,
)
def reject_application(
    application_id: str,
    payload: AdminApplicationReviewIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    app = _load_application(db, application_id)
    if app.status != "pending":
        bad_request(f"Application already {app.status}")

    app.status = "rejected"
    app.admin_note = payload.admin_note if payload else None
    app.reviewed_by = actor.id
    app.reviewed_at = dt.datetime.now(dt.timezone.utc)
    log_action(
        db,
        actor_id=actor.id,
        action="freelancer.reject",
        entity="freelancer_application",
        entity_id=str(app.id),
        meta={"user_id": str(app.user_id)},
    )
    db.commit()
    db.refresh(app)
    return serialize_application(db, app)
