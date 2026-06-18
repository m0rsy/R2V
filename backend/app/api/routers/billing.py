from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_db, get_current_user
from app.api.schemas.billing import CheckoutIn, CheckoutOut, SubscriptionCheckoutOut
from app.core.errors import not_found, bad_request, forbidden
from app.db.models.marketplace import Asset, Purchase
from app.services.stripe_service import create_asset_checkout_session, create_subscription_checkout_session
from app.services.entitlements import is_entitled_to_asset

router = APIRouter()

@router.post("/checkout/asset", response_model=CheckoutOut)
def checkout_asset(payload: CheckoutIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    a = db.get(Asset, payload.asset_id)
    if not a: not_found()
    if not a.is_paid or a.price <= 0:
        bad_request("Asset is free or has invalid price")
    entitled, reason = is_entitled_to_asset(db, user.id, a)
    if entitled:
        forbidden(f"Already entitled: {reason}")
    url = create_asset_checkout_session(user_id=str(user.id), asset_id=str(a.id), title=a.title, amount_cents=a.price, currency=a.currency)
    # record pending purchase
    p = Purchase(user_id=user.id, asset_id=a.id, status="pending", amount=a.price, currency=a.currency)
    db.add(p); db.commit()
    return CheckoutOut(checkout_url=url)

@router.post("/checkout/subscription", response_model=SubscriptionCheckoutOut)
def checkout_subscription(db: Session = Depends(get_db), user = Depends(get_current_user)):
    url = create_subscription_checkout_session(user_id=str(user.id))
    return SubscriptionCheckoutOut(checkout_url=url)
