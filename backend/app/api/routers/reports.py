from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db, require_admin
from app.api.schemas.report import (
    VALID_TARGET_TYPES,
    AdminReportsOut,
    ReportCreateIn,
    ReportOut,
    ReportReviewIn,
)
from app.core.errors import bad_request, conflict, not_found
from app.db.models.report import Report
from app.db.models.user import User, UserProfile
from app.services.audit import log_action

router = APIRouter()
admin_router = APIRouter()


def _serialize(db: Session, report: Report) -> ReportOut:
    username = db.execute(
        select(UserProfile.username).where(UserProfile.user_id == report.reporter_id)
    ).scalar_one_or_none()
    return ReportOut(
        id=str(report.id),
        reporter_id=str(report.reporter_id),
        reporter_username=username,
        target_type=report.target_type,
        target_id=report.target_id,
        reason=report.reason,
        description=report.description,
        status=report.status,
        admin_note=report.admin_note,
        created_at=report.created_at.isoformat(),
        resolved_at=report.resolved_at.isoformat() if report.resolved_at else None,
    )


# --------------------------------------------------------------------------- #
# User-facing: submit a report
# --------------------------------------------------------------------------- #


# Path is "/" (not "") because the router is mounted under prefix="/reports";
# FastAPI 0.137+ forbids an empty path reachable from a prefix-less top-level
# include. A request to "/reports" still works via Starlette's slash redirect.
@router.post("/", response_model=ReportOut)
def create_report(
    payload: ReportCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    target_type = payload.target_type.strip().lower()
    if target_type not in VALID_TARGET_TYPES:
        bad_request(f"Invalid target_type. Allowed: {', '.join(sorted(VALID_TARGET_TYPES))}")

    # Block duplicate spam: one open (pending) report per reporter+target.
    existing = db.execute(
        select(Report).where(
            Report.reporter_id == user.id,
            Report.target_type == target_type,
            Report.target_id == payload.target_id,
            Report.status == "pending",
        )
    ).scalar_one_or_none()
    if existing:
        conflict("You already reported this. Our team will review it.")

    report = Report(
        reporter_id=user.id,
        target_type=target_type,
        target_id=payload.target_id.strip(),
        reason=payload.reason.strip(),
        description=(payload.description or None),
        status="pending",
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return _serialize(db, report)


@router.get("/me", response_model=list[ReportOut])
def my_reports(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = db.execute(
        select(Report)
        .where(Report.reporter_id == user.id)
        .order_by(desc(Report.created_at))
        .limit(100)
    ).scalars().all()
    return [_serialize(db, r) for r in rows]


# --------------------------------------------------------------------------- #
# Admin: review reports
# --------------------------------------------------------------------------- #


def _count(db: Session, stmt) -> int:
    return int(db.execute(stmt).scalar_one() or 0)


@admin_router.get("/reports", response_model=AdminReportsOut)
def list_reports(
    status: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    stmt = select(Report).order_by(desc(Report.created_at))
    if status in ("pending", "reviewed", "resolved", "rejected"):
        stmt = stmt.where(Report.status == status)
    rows = db.execute(stmt.limit(200)).scalars().all()

    def _status_count(value: str) -> int:
        return _count(
            db, select(func.count()).select_from(Report).where(Report.status == value)
        )

    return AdminReportsOut(
        total=_count(db, select(func.count()).select_from(Report)),
        pending=_status_count("pending"),
        resolved=_status_count("resolved"),
        rejected=_status_count("rejected"),
        reports=[_serialize(db, r).model_dump() for r in rows],
    )


def _load_report(db: Session, report_id: str) -> Report:
    try:
        rid = uuid.UUID(report_id)
    except (ValueError, TypeError):
        bad_request("Invalid report id")
    report = db.get(Report, rid)
    if not report:
        not_found("Report not found")
    return report


def _review(db: Session, report_id: str, actor: User, status: str, note: str | None) -> ReportOut:
    report = _load_report(db, report_id)
    if report.status in ("resolved", "rejected"):
        bad_request(f"Report already {report.status}")
    report.status = status
    report.admin_note = note
    report.reviewed_by = actor.id
    report.resolved_at = dt.datetime.now(dt.timezone.utc)
    log_action(
        db,
        actor_id=actor.id,
        action=f"report.{status}",
        entity="report",
        entity_id=str(report.id),
        meta={"target_type": report.target_type, "target_id": report.target_id},
    )
    db.commit()
    db.refresh(report)
    return _serialize(db, report)


@admin_router.post("/reports/{report_id}/resolve", response_model=ReportOut)
def resolve_report(
    report_id: str,
    payload: ReportReviewIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    return _review(db, report_id, actor, "resolved", payload.admin_note if payload else None)


@admin_router.post("/reports/{report_id}/reject", response_model=ReportOut)
def reject_report(
    report_id: str,
    payload: ReportReviewIn | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(require_admin),
):
    return _review(db, report_id, actor, "rejected", payload.admin_note if payload else None)
