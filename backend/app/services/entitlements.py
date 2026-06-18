from __future__ import annotations
from sqlalchemy.orm import Session
from sqlalchemy import select, and_
from app.db.models.marketplace import Asset, Purchase, Subscription

def is_entitled_to_asset(db: Session, user_id, asset: Asset) -> tuple[bool, str]:
    if asset.visibility != "published":
        return False, "asset_not_published"
    if not asset.is_paid:
        return True, "free"
    q = select(Purchase).where(and_(Purchase.user_id == user_id, Purchase.asset_id == asset.id, Purchase.status == "succeeded"))
    if db.execute(q).scalar_one_or_none():
        return True, "purchase"
    sq = select(Subscription).where(and_(Subscription.user_id == user_id, Subscription.status.in_(["active", "trialing"])))
    if db.execute(sq).scalar_one_or_none():
        return True, "subscription"
    return False, "not_entitled"
