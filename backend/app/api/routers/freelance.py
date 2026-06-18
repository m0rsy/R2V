from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, File, Query, UploadFile
from sqlalchemy import and_, desc, func, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.api.schemas.freelance import (
    DeliveryIn,
    FreelancerApplicationIn,
    FreelancerApplicationOut,
    FreelancerProfileIn,
    MessageIn,
    OrderCreateIn,
    OrderStatusIn,
    ReviewIn,
    RevisionIn,
    ServiceIn,
    ServiceUpdateIn,
)
from app.core.errors import bad_request, conflict, forbidden, not_found
from app.core.permissions import ROLE_FREELANCER
from app.db.models.freelance import FreelancerApplication
from app.db.models.freelance_market import (
    AVAILABILITY_STATUSES,
    FREELANCE_CATEGORIES,
    ORDER_STATUSES,
    FreelanceChatMessage,
    FreelanceOrder,
    FreelanceReview,
    FreelanceService,
    FreelancerProfile,
)
from app.db.models.user import User
from app.services import freelance as fl

router = APIRouter()


def serialize_application(db: Session, app: FreelancerApplication) -> FreelancerApplicationOut:
    return FreelancerApplicationOut(**fl.serialize_application(db, app))


def promote_to_freelancer(db: Session, app: FreelancerApplication) -> None:
    user = db.get(User, app.user_id)
    if not user:
        not_found("Applicant not found")
    user.role = ROLE_FREELANCER
    profile = db.execute(
        select(FreelancerProfile).where(FreelancerProfile.user_id == app.user_id)
    ).scalar_one_or_none()
    if profile is None:
        profile = FreelancerProfile(
            user_id=app.user_id,
            display_name=app.full_name,
            title=app.title,
            skills=app.skills if isinstance(app.skills, list) else [],
            categories=[],
            portfolio_links=app.portfolio_links if isinstance(app.portfolio_links, list) else [],
            status="approved",
        )
        db.add(profile)
    else:
        profile.display_name = app.full_name
        profile.title = app.title
        profile.skills = app.skills if isinstance(app.skills, list) else []
        profile.portfolio_links = app.portfolio_links if isinstance(app.portfolio_links, list) else []
        profile.status = "approved"
    db.flush()


def _profile_out(user: User, profile) -> dict:
    return {
        "id": str(user.id),
        "user_id": str(user.id),
        "username": getattr(profile, "username", None) or user.email.split("@")[0],
        "email": user.email,
        "display_name": getattr(profile, "username", None) or user.email.split("@")[0],
        "title": "3D Freelancer",
        "role": "3D Freelancer",
        "bio": getattr(profile, "bio", None),
        "avatar_url": getattr(profile, "avatar_url", None),
        "cover_url": None,
        "rating": 0,
        "rating_average": 0,
        "reviews": 0,
        "rating_count": 0,
        "hourly_rate": None,
        "starting_price": None,
        "featured": False,
        "skills": [],
        "categories": [],
        "status": "approved",
        "availability": "available",
        "completed_jobs_count": 0,
    }


def _uuid(value: str, label: str = "id") -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError):
        bad_request(f"Invalid {label}")


def _get_profile(db: Session, profile_id: str) -> FreelancerProfile:
    pid = _uuid(profile_id, "freelancer id")
    profile = db.get(FreelancerProfile, pid)
    if not profile:
        not_found("Freelancer not found")
    return profile


def _get_service(db: Session, service_id: str) -> FreelanceService:
    sid = _uuid(service_id, "service id")
    service = db.get(FreelanceService, sid)
    if not service:
        not_found("Service not found")
    return service


def _get_order(db: Session, order_id: str) -> FreelanceOrder:
    oid = _uuid(order_id, "order id")
    order = db.get(FreelanceOrder, oid)
    if not order:
        not_found("Order not found")
    return order


def _order_role(db: Session, order: FreelanceOrder, user: User) -> tuple[str, FreelancerProfile]:
    profile = db.get(FreelancerProfile, order.freelancer_id)
    if not profile:
        not_found("Freelancer profile not found")
    return fl.order_role(order, profile, user), profile


def _apply_order_status(order: FreelanceOrder, status: str, *, note: str | None = None) -> None:
    status = fl.validate_order_status(status)
    order.status = status
    if status == "revision_requested":
        order.revision_note = note
    if status == "completed":
        order.completed_at = fl.utcnow()
    if status == "disputed":
        order.dispute_reason = note
    order.updated_at = fl.utcnow()


@router.get("/categories")
def categories():
    return [{"id": c.lower().replace(" ", "_"), "name": c} for c in FREELANCE_CATEGORIES]


@router.get("/freelancers")
def list_freelancers(
    db: Session = Depends(get_db),
    search: str = Query(default="", max_length=120),
    category: str | None = Query(default=None),
    skill: str | None = Query(default=None),
    min_rating: float = Query(default=0, ge=0, le=5),
    max_price: float | None = Query(default=None, ge=0),
    availability: str | None = Query(default=None),
):
    stmt = select(FreelancerProfile).where(FreelancerProfile.status == "approved")
    if availability:
        stmt = stmt.where(FreelancerProfile.availability == availability)
    if min_rating:
        stmt = stmt.where(FreelancerProfile.rating_average >= min_rating)
    if max_price is not None:
        stmt = stmt.where(
            or_(
                FreelancerProfile.starting_price.is_(None),
                FreelancerProfile.starting_price <= max_price,
            )
        )
    rows = db.execute(
        stmt.order_by(desc(FreelancerProfile.rating_average), desc(FreelancerProfile.completed_jobs_count))
    ).scalars().all()
    term = search.strip().lower()
    out = []
    for profile in rows:
        payload = fl.serialize_profile(db, profile)
        hay = " ".join(
            [
                payload.get("display_name") or "",
                payload.get("title") or "",
                payload.get("bio") or "",
                " ".join(payload.get("skills") or []),
                " ".join(payload.get("categories") or []),
            ]
        ).lower()
        if term and term not in hay:
            continue
        if category and category not in (payload.get("categories") or []):
            continue
        if skill and skill.lower() not in [s.lower() for s in payload.get("skills") or []]:
            continue
        out.append(payload)
    return out


@router.get("/profiles")
def list_profiles_alias(
    db: Session = Depends(get_db),
    search: str = Query(default="", max_length=120),
):
    return list_freelancers(db=db, search=search)


@router.get("/freelancers/{freelancer_id}")
def get_freelancer(freelancer_id: str, db: Session = Depends(get_db)):
    profile = _get_profile(db, freelancer_id)
    if profile.status != "approved":
        not_found("Freelancer not found")
    return fl.serialize_profile(db, profile, include_services=True)


@router.get("/profiles/{profile_id}")
def get_profile_alias(profile_id: str, db: Session = Depends(get_db)):
    return get_freelancer(profile_id, db)


@router.get("/services")
def list_services(
    db: Session = Depends(get_db),
    search: str = Query(default="", max_length=120),
    category: str | None = Query(default=None),
    min_price: float | None = Query(default=None, ge=0),
    max_price: float | None = Query(default=None, ge=0),
):
    stmt = (
        select(FreelanceService)
        .join(FreelancerProfile, FreelancerProfile.id == FreelanceService.freelancer_id)
        .where(FreelanceService.status == "active", FreelancerProfile.status == "approved")
    )
    if category:
        stmt = stmt.where(FreelanceService.category == category)
    if min_price is not None:
        stmt = stmt.where(FreelanceService.starting_price >= min_price)
    if max_price is not None:
        stmt = stmt.where(FreelanceService.starting_price <= max_price)
    rows = db.execute(stmt.order_by(desc(FreelanceService.created_at))).scalars().all()
    term = search.strip().lower()
    out = []
    for service in rows:
        payload = fl.serialize_service(db, service)
        freelancer = payload.get("freelancer") or {}
        hay = " ".join(
            [
                payload.get("title") or "",
                payload.get("description") or "",
                payload.get("category") or "",
                " ".join(payload.get("tags") or []),
                freelancer.get("display_name") or "",
            ]
        ).lower()
        if term and term not in hay:
            continue
        out.append(payload)
    return out


@router.get("/services/{service_id}")
def get_service(service_id: str, db: Session = Depends(get_db)):
    service = _get_service(db, service_id)
    profile = db.get(FreelancerProfile, service.freelancer_id)
    if service.status != "active" or not profile or profile.status != "approved":
        not_found("Service not found")
    return fl.serialize_service(db, service)


@router.post("/apply")
def apply(
    payload: FreelancerApplicationIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if db.execute(
        select(FreelancerProfile.id).where(
            FreelancerProfile.user_id == user.id, FreelancerProfile.status == "approved"
        )
    ).first():
        bad_request("You are already an approved freelancer")
    existing = db.execute(
        select(FreelancerApplication)
        .where(
            FreelancerApplication.user_id == user.id,
            FreelancerApplication.status.in_(["pending_review", "needs_more_info"]),
        )
        .order_by(desc(FreelancerApplication.created_at))
    ).scalars().first()
    if existing:
        conflict("You already have an application under review")
    links = fl.clean_list(payload.portfolio_links)
    if payload.portfolio_url:
        links = fl.clean_list([*links, payload.portfolio_url])
    app = FreelancerApplication(
        user_id=user.id,
        full_name=(payload.full_name or payload.display_name or "").strip(),
        title=payload.title.strip(),
        skills=fl.clean_list(payload.skills),
        experience=payload.experience,
        portfolio_links=links,
        expected_price_range=payload.expected_price_range,
        message=payload.message,
        status="pending_review",
    )
    db.add(app)
    db.commit()
    db.refresh(app)
    return fl.serialize_application(db, app)


@router.post("/applications")
def apply_alias(payload: FreelancerApplicationIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return apply(payload, db, user)


@router.get("/my-application")
def my_application(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    app = db.execute(
        select(FreelancerApplication)
        .where(FreelancerApplication.user_id == user.id)
        .order_by(desc(FreelancerApplication.created_at))
        .limit(1)
    ).scalar_one_or_none()
    return fl.serialize_application(db, app) if app else {}


@router.get("/applications/me")
def my_application_alias(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return my_application(db, user)


@router.post("/orders")
def create_order(
    payload: OrderCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    service = None
    profile = None
    if payload.service_id:
        service = _get_service(db, payload.service_id)
        if service.status != "active":
            bad_request("Service is not available")
        profile = db.get(FreelancerProfile, service.freelancer_id)
    elif payload.freelancer_id:
        profile = _get_profile(db, payload.freelancer_id)
    else:
        bad_request("Choose a freelancer or service")
    if not profile or profile.status != "approved":
        bad_request("Freelancer is not available")
    if profile.user_id == user.id:
        bad_request("You cannot order your own service")
    order = FreelanceOrder(
        client_id=user.id,
        freelancer_id=profile.id,
        service_id=service.id if service else None,
        title=payload.title.strip(),
        requirements=payload.requirements.strip(),
        budget=payload.budget,
        deadline=payload.deadline,
        attachments=fl.clean_list(payload.attachments, limit=80),
        status="pending",
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/direct")
def create_direct_order(payload: OrderCreateIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return create_order(payload, db, user)


@router.get("/my-orders")
def my_orders(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    status: str | None = Query(default=None),
):
    profile = db.execute(
        select(FreelancerProfile).where(FreelancerProfile.user_id == user.id)
    ).scalar_one_or_none()
    conds = [FreelanceOrder.client_id == user.id]
    if profile:
        conds.append(FreelanceOrder.freelancer_id == profile.id)
    stmt = select(FreelanceOrder).where(or_(*conds))
    if status:
        stmt = stmt.where(FreelanceOrder.status == status)
    rows = db.execute(stmt.order_by(desc(FreelanceOrder.created_at)).limit(200)).scalars().all()
    return [fl.serialize_order(db, order, user) for order in rows]


@router.get("/orders")
def orders_alias(db: Session = Depends(get_db), user: User = Depends(get_current_user), status: str | None = None, role: str | None = None):
    return my_orders(db, user, status)


@router.get("/incoming-orders")
def incoming_orders(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = fl.require_approved_profile(db, user)
    rows = db.execute(
        select(FreelanceOrder)
        .where(FreelanceOrder.freelancer_id == profile.id)
        .order_by(desc(FreelanceOrder.created_at))
    ).scalars().all()
    return [fl.serialize_order(db, order, user) for order in rows]


@router.get("/orders/{order_id}")
def get_order(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    _order_role(db, order, user)
    return fl.serialize_order(db, order, user)


@router.patch("/orders/{order_id}/status")
def patch_order_status(
    order_id: str,
    payload: OrderStatusIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role not in ("client", "freelancer", "admin"):
        forbidden("You cannot update this order")
    if role == "client" and payload.status not in ("cancelled", "disputed"):
        forbidden("Clients should use the revision/complete/dispute actions")
    if role == "freelancer" and payload.status not in ("accepted", "rejected", "in_progress"):
        forbidden("Freelancers should use the accept/reject/deliver actions")
    _apply_order_status(order, payload.status, note=payload.reason)
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.patch("/orders/{order_id}/accept")
def accept_order(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role != "freelancer":
        forbidden("Only the assigned freelancer can accept")
    if order.status != "pending":
        bad_request("Only pending orders can be accepted")
    _apply_order_status(order, "accepted")
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.patch("/orders/{order_id}/reject")
def reject_order(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role != "freelancer":
        forbidden("Only the assigned freelancer can reject")
    if order.status != "pending":
        bad_request("Only pending orders can be rejected")
    _apply_order_status(order, "rejected")
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/{order_id}/deliver")
def deliver_order(
    order_id: str,
    payload: DeliveryIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role != "freelancer":
        forbidden("Only the assigned freelancer can deliver files")
    if order.status not in ("accepted", "in_progress", "revision_requested"):
        bad_request("This order is not ready for delivery")
    order.delivery_files = fl.clean_list(payload.files, limit=80)
    order.status = "delivered"
    order.updated_at = fl.utcnow()
    if payload.message:
        db.add(
            FreelanceChatMessage(
                order_id=order.id,
                sender_id=user.id,
                message=payload.message,
                attachments=order.delivery_files,
            )
        )
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/{order_id}/submit-delivery")
async def submit_delivery_alias(
    order_id: str,
    file: UploadFile | None = File(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role != "freelancer":
        forbidden("Only the assigned freelancer can deliver files")
    files = list(order.delivery_files or [])
    if file is not None:
        files.append(await fl.upload_to_freelance_bucket(file, prefix=f"orders/{order.id}/deliveries"))
    order.delivery_files = files
    order.status = "delivered"
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/{order_id}/request-revision")
def request_revision(order_id: str, payload: RevisionIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    role, _profile = _order_role(db, order, user)
    if role != "client":
        forbidden("Only the client can request revision")
    if order.status != "delivered":
        bad_request("Revisions can only be requested after delivery")
    _apply_order_status(order, "revision_requested", note=payload.note)
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/{order_id}/complete")
def complete_order(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    role, profile = _order_role(db, order, user)
    if role != "client":
        forbidden("Only the client can complete the order")
    if order.status not in ("delivered", "accepted", "in_progress"):
        bad_request("This order cannot be completed yet")
    _apply_order_status(order, "completed")
    fl.recompute_profile_stats(db, profile)
    db.commit()
    db.refresh(order)
    return fl.serialize_order(db, order, user)


@router.post("/orders/{order_id}/approve")
def approve_alias(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return complete_order(order_id, db, user)


@router.post("/orders/{order_id}/review")
def review_order(order_id: str, payload: ReviewIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    role, profile = _order_role(db, order, user)
    if role != "client":
        forbidden("Only the client can review this order")
    if order.status != "completed":
        bad_request("Reviews can only be created after order completion")
    if db.execute(
        select(FreelanceReview.id).where(
            FreelanceReview.order_id == order.id,
            FreelanceReview.client_id == user.id,
        )
    ).first():
        conflict("You have already reviewed this order")
    review = FreelanceReview(
        order_id=order.id,
        client_id=user.id,
        freelancer_id=profile.id,
        rating=payload.rating,
        quality_rating=payload.quality_rating,
        communication_rating=payload.communication_rating,
        delivery_rating=payload.delivery_rating,
        comment=payload.comment,
    )
    db.add(review)
    db.flush()
    fl.recompute_profile_stats(db, profile)
    db.commit()
    db.refresh(review)
    return fl.serialize_review(db, review)


@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = db.execute(
        select(FreelancerProfile).where(FreelancerProfile.user_id == user.id)
    ).scalar_one_or_none()
    profile_id = profile.id if profile else None
    service_count = db.execute(
        select(func.count(FreelanceService.id)).where(FreelanceService.freelancer_id == profile_id)
    ).scalar_one() if profile_id else 0
    incoming = db.execute(
        select(func.count(FreelanceOrder.id)).where(
            FreelanceOrder.freelancer_id == profile_id,
            FreelanceOrder.status == "pending",
        )
    ).scalar_one() if profile_id else 0
    active = db.execute(
        select(func.count(FreelanceOrder.id)).where(
            FreelanceOrder.freelancer_id == profile_id,
            FreelanceOrder.status.in_(["accepted", "in_progress", "delivered", "revision_requested"]),
        )
    ).scalar_one() if profile_id else 0
    earnings = db.execute(
        select(func.coalesce(func.sum(FreelanceOrder.budget), 0)).where(
            FreelanceOrder.freelancer_id == profile_id,
            FreelanceOrder.status == "completed",
        )
    ).scalar_one() if profile_id else 0
    client_orders = db.execute(
        select(func.count(FreelanceOrder.id)).where(FreelanceOrder.client_id == user.id)
    ).scalar_one()
    return {
        "is_freelancer": bool(profile and profile.status == "approved"),
        "profile": fl.serialize_profile(db, profile) if profile else None,
        "freelancer": {
            "active_orders": int(active or 0),
            "incoming_orders": int(incoming or 0),
            "completed_jobs": profile.completed_jobs_count if profile else 0,
            "earnings": float(earnings or 0),
            "service_count": int(service_count or 0),
            "rating": float(profile.rating_average or 0) if profile else 0,
        },
        "client": {
            "active_projects": int(client_orders or 0),
            "proposals_received": 0,
            "total_spent": float(
                db.execute(
                    select(func.coalesce(func.sum(FreelanceOrder.budget), 0)).where(
                        FreelanceOrder.client_id == user.id,
                        FreelanceOrder.status == "completed",
                    )
                ).scalar_one()
                or 0
            ),
            "pending_deliveries": int(
                db.execute(
                    select(func.count(FreelanceOrder.id)).where(
                        FreelanceOrder.client_id == user.id,
                        FreelanceOrder.status == "delivered",
                    )
                ).scalar_one()
                or 0
            ),
        },
    }


@router.patch("/profile")
def update_profile(payload: FreelancerProfileIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = fl.require_approved_profile(db, user)
    if payload.display_name is not None:
        profile.display_name = payload.display_name
    if payload.title is not None:
        profile.title = payload.title
    if payload.bio is not None:
        profile.bio = payload.bio
    if payload.skills is not None:
        profile.skills = payload.skills
    if payload.categories is not None:
        profile.categories = payload.categories
    if payload.hourly_rate is not None:
        profile.hourly_rate = payload.hourly_rate
    if payload.starting_price is not None:
        profile.starting_price = payload.starting_price
    if payload.profile_image is not None:
        profile.profile_image = payload.profile_image
    if payload.portfolio_links is not None:
        profile.portfolio_links = payload.portfolio_links
    if payload.availability is not None:
        profile.availability = payload.availability
    db.commit()
    db.refresh(profile)
    return fl.serialize_profile(db, profile)


@router.get("/profile/me")
def my_profile(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = db.execute(select(FreelancerProfile).where(FreelancerProfile.user_id == user.id)).scalar_one_or_none()
    return fl.serialize_profile(db, profile) if profile else {}


@router.put("/profile/me")
def upsert_profile_alias(payload: FreelancerProfileIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return update_profile(payload, db, user)


@router.patch("/availability")
def update_availability(payload: dict, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = fl.require_approved_profile(db, user)
    status = str(payload.get("availability") or payload.get("status") or "").strip()
    if status not in AVAILABILITY_STATUSES:
        bad_request("Invalid availability")
    profile.availability = status
    db.commit()
    return fl.serialize_profile(db, profile)


@router.post("/services")
def create_service(payload: ServiceIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    profile = fl.require_approved_profile(db, user)
    service = FreelanceService(
        freelancer_id=profile.id,
        title=payload.title,
        description=payload.description,
        category=payload.category,
        tags=payload.tags,
        starting_price=payload.starting_price,
        delivery_days=payload.delivery_days,
        revisions=payload.revisions,
        file_formats=payload.file_formats,
        images=payload.images,
        status=payload.status,
    )
    db.add(service)
    db.commit()
    db.refresh(service)
    return fl.serialize_service(db, service)


@router.patch("/services/{service_id}")
def update_service(service_id: str, payload: ServiceUpdateIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    service = _get_service(db, service_id)
    profile = fl.require_approved_profile(db, user)
    if service.freelancer_id != profile.id:
        forbidden("You can only edit your own services")
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        if key == "status" and value is not None:
            value = fl.validate_service_status(value)
        setattr(service, key, value)
    db.commit()
    db.refresh(service)
    return fl.serialize_service(db, service)


@router.delete("/services/{service_id}")
def delete_service(service_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    service = _get_service(db, service_id)
    profile = fl.require_approved_profile(db, user)
    if service.freelancer_id != profile.id:
        forbidden("You can only delete your own services")
    db.delete(service)
    db.commit()
    return {"deleted": True}


@router.get("/orders/{order_id}/messages")
def order_messages(order_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    _order_role(db, order, user)
    rows = db.execute(
        select(FreelanceChatMessage)
        .where(FreelanceChatMessage.order_id == order.id)
        .order_by(FreelanceChatMessage.created_at)
        .limit(200)
    ).scalars().all()
    return {
        "order": fl.serialize_order(db, order, user),
        "messages": [fl.serialize_message(db, msg, user) for msg in rows],
    }


@router.post("/orders/{order_id}/messages")
def post_order_message(order_id: str, payload: MessageIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    _order_role(db, order, user)
    text = (payload.message or payload.text or "").strip()
    attachments = fl.clean_list(payload.attachments, limit=40)
    if not text and not attachments:
        bad_request("Message or attachment is required")
    msg = FreelanceChatMessage(order_id=order.id, sender_id=user.id, message=text or None, attachments=attachments)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return fl.serialize_message(db, msg, user)


@router.post("/orders/{order_id}/messages/attachment")
async def post_order_attachment(order_id: str, file: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    _order_role(db, order, user)
    attachment = await fl.upload_to_freelance_bucket(file, prefix=f"orders/{order.id}/messages")
    msg = FreelanceChatMessage(order_id=order.id, sender_id=user.id, attachments=[attachment])
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return fl.serialize_message(db, msg, user)


@router.post("/orders/{order_id}/messages/voice-note")
async def post_voice_note(order_id: str, file: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    order = _get_order(db, order_id)
    _order_role(db, order, user)
    attachment = await fl.upload_to_freelance_bucket(file, prefix=f"orders/{order.id}/voice")
    msg = FreelanceChatMessage(
        order_id=order.id,
        sender_id=user.id,
        attachments=[attachment],
        voice_note_url=attachment.get("url"),
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return fl.serialize_message(db, msg, user)
