from __future__ import annotations
from pydantic import BaseModel

class CheckoutIn(BaseModel):
    asset_id: str

class CheckoutOut(BaseModel):
    checkout_url: str

class SubscriptionCheckoutOut(BaseModel):
    checkout_url: str
