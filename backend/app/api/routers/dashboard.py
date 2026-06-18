from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select, func
from app.api.deps import get_db, get_current_user
from app.db.models.marketplace import Asset, Download
from app.db.models.jobs import AIJob, ScanJob

router = APIRouter()

@router.get("/me")
def my_dashboard(db: Session = Depends(get_db), user = Depends(get_current_user)):
    assets = db.execute(select(func.count()).select_from(Asset).where(Asset.creator_id == user.id)).scalar_one()
    downloads = db.execute(
        select(func.count())
        .select_from(Download)
        .join(Asset, Asset.id == Download.asset_id)
        .where(Asset.creator_id == user.id)
    ).scalar_one()
    ai_jobs = db.execute(select(func.count()).select_from(AIJob).where(AIJob.user_id == user.id)).scalar_one()
    scan_jobs = db.execute(select(func.count()).select_from(ScanJob).where(ScanJob.user_id == user.id)).scalar_one()
    return {"assets": assets, "downloads": downloads, "ai_jobs": ai_jobs, "scan_jobs": scan_jobs}
