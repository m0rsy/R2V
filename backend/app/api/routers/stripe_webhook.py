from __future__ import annotations
import datetime as dt
from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy.orm import Session
from sqlalchemy import select, desc
from app.api.deps import get_db
from app.core.errors import bad_request
from app.db.models.marketplace import Purchase, Subscription
from app.services.stripe_service import verify_webhook

router = APIRouter()

@router.post("/webhook")
async def webhook(request: Request, stripe_signature: str | None = Header(default=None, alias="Stripe-Signature"), db: Session = Depends(get_db)):
    if not stripe_signature:
        bad_request("Missing Stripe-Signature header")
    payload = await request.body()
    try:
        event = verify_webhook(payload, stripe_signature)
    except Exception as e:
        bad_request(f"Webhook verification failed: {e}")
    etype = event["type"]
    data = event["data"]["object"]
    # Minimal handlers (extend as needed)
    if etype == "checkout.session.completed":
        meta = data.get("metadata") or {}
        if meta.get("kind") == "asset_purchase":
            user_id = meta.get("user_id"); asset_id = meta.get("asset_id")
            if user_id and asset_id:
                # mark latest pending purchase succeeded and attach payment_intent if present
                stmt = select(Purchase).where(Purchase.user_id==user_id, Purchase.asset_id==asset_id, Purchase.status=="pending").order_by(desc(Purchase.created_at))
                p = db.execute(stmt).scalars().first()
                if p:
                    p.status = "succeeded"
                    p.stripe_payment_intent = data.get("payment_intent")
                    db.commit()
        if meta.get("kind") == "subscription":
            # subscription id lives on session.subscriptions
            sub_id = data.get("subscription")
            customer = data.get("customer")
            user_id = meta.get("user_id")
            if sub_id and customer and user_id:
                s = Subscription(user_id=user_id, stripe_customer_id=customer, stripe_subscription_id=sub_id, status="active", plan="default", current_period_end=None)
                db.add(s); db.commit()
    elif etype.startswith("customer.subscription."):
        sub = data
        sub_id = sub.get("id")
        if sub_id:
            s = db.execute(select(Subscription).where(Subscription.stripe_subscription_id==sub_id)).scalar_one_or_none()
            if s:
                s.status = sub.get("status","active")
                cpe = sub.get("current_period_end")
                if cpe:
                    s.current_period_end = dt.datetime.fromtimestamp(int(cpe), tz=dt.timezone.utc)
                db.commit()

    return {"received": True}