from __future__ import annotations
import stripe
from app.core.config import settings

def configure_stripe() -> None:
    stripe.api_key = settings.stripe_secret_key

def create_asset_checkout_session(*, user_id: str, asset_id: str, title: str, amount_cents: int, currency: str) -> str:
    configure_stripe()
    session = stripe.checkout.Session.create(
        mode="payment",
        success_url=settings.stripe_success_url,
        cancel_url=settings.stripe_cancel_url,
        line_items=[{"price_data": {"currency": currency, "product_data": {"name": title}, "unit_amount": amount_cents}, "quantity": 1}],
        metadata={"user_id": user_id, "asset_id": asset_id, "kind": "asset_purchase"},
    )
    return session.url

def create_subscription_checkout_session(*, user_id: str) -> str:
    configure_stripe()
    if not settings.stripe_subscription_price_id:
        raise ValueError("STRIPE_SUBSCRIPTION_PRICE_ID not configured")
    session = stripe.checkout.Session.create(
        mode="subscription",
        success_url=settings.stripe_success_url,
        cancel_url=settings.stripe_cancel_url,
        line_items=[{"price": settings.stripe_subscription_price_id, "quantity": 1}],
        metadata={"user_id": user_id, "kind": "subscription"},
    )
    return session.url

def verify_webhook(payload: bytes, sig_header: str):
    configure_stripe()
    return stripe.Webhook.construct_event(payload, sig_header, settings.stripe_webhook_secret)
