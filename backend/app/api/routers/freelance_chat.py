from __future__ import annotations

from fastapi import APIRouter

# Freelance chat is intentionally implemented in app.api.routers.freelance and
# bound directly to /freelance/orders/{order_id}/messages. This empty router is
# kept so the central router import remains stable while the legacy
# conversation-based freelance chat is fully removed.

router = APIRouter()
