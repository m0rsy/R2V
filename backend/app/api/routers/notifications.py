from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select, desc, func, update
from app.api.deps import get_db, get_current_user
from app.core.errors import not_found
from app.db.models.social import Notification

router = APIRouter()

# Path "/" (not "") — see reports.py: empty paths are rejected by FastAPI 0.137+
# when reached from the prefix-less top-level include. "/notifications" still
# resolves via Starlette's trailing-slash redirect.
@router.get("/", response_model=list[dict])
def list_notifications(limit: int = 50, offset: int = 0, db: Session = Depends(get_db), user = Depends(get_current_user)):
    q = select(Notification).where(Notification.user_id == user.id).order_by(desc(Notification.created_at)).limit(limit).offset(offset)
    items = db.execute(q).scalars().all()
    return [{"id": str(n.id), "type": n.type, "payload": n.payload_json, "is_read": n.is_read, "created_at": n.created_at.isoformat()} for n in items]

# Static routes are declared before the dynamic "/{notif_id}/read" route so the
# router never tries to treat "unread-count"/"read-all" as a notification id.
@router.get("/unread-count")
def unread_count(db: Session = Depends(get_db), user = Depends(get_current_user)):
    count = db.execute(
        select(func.count()).select_from(Notification).where(
            Notification.user_id == user.id, Notification.is_read == False  # noqa: E712
        )
    ).scalar_one()
    return {"unread_count": count}

@router.post("/read-all")
def mark_all_read(db: Session = Depends(get_db), user = Depends(get_current_user)):
    result = db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
        .values(is_read=True)
    )
    db.commit()
    return {"detail": "ok", "updated": result.rowcount}

@router.post("/{notif_id}/read")
def mark_read(notif_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    n = db.get(Notification, notif_id)
    if not n or n.user_id != user.id:
        not_found()
    n.is_read = True
    db.commit()
    return {"detail": "ok"}
