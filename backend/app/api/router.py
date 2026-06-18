from fastapi import APIRouter

import app.api.routers.admin as admin
import app.api.routers.admin_management as admin_management
import app.api.routers.admin_freelance as admin_freelance
import app.api.routers.ai_jobs as ai_jobs
import app.api.routers.ai_chat as ai_chat
import app.api.routers.chat as chat
import app.api.routers.assets_download as assets_download
import app.api.routers.auth as auth
import app.api.routers.billing as billing
import app.api.routers.dashboard as dashboard
import app.api.routers.freelance as freelance
import app.api.routers.freelance_chat as freelance_chat
import app.api.routers.marketplace as marketplace
import app.api.routers.me as me
import app.api.routers.notifications as notifications
import app.api.routers.photogrammetry as photogrammetry
import app.api.routers.reports as reports
import app.api.routers.scan_jobs as scan_jobs
import app.api.routers.social as social
import app.api.routers.stripe_webhook as stripe_webhook

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(me.router, tags=["me"])
api_router.include_router(ai_jobs.router, prefix="/ai", tags=["ai"])
api_router.include_router(ai_jobs.legacy_router, tags=["ai"])
api_router.include_router(ai_chat.router, prefix="/ai", tags=["ai-chat"])
api_router.include_router(scan_jobs.router, prefix="/scan", tags=["scan"])
api_router.include_router(photogrammetry.router, prefix="/api/photogrammetry", tags=["photogrammetry"])
api_router.include_router(marketplace.router, prefix="/marketplace", tags=["marketplace"])
api_router.include_router(freelance.router, prefix="/freelance", tags=["freelance"])
api_router.include_router(freelance_chat.router, prefix="/freelance", tags=["freelance-chat"])
api_router.include_router(assets_download.router, tags=["downloads"])
api_router.include_router(social.router, prefix="/social", tags=["social"])
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(admin_management.router, prefix="/admin", tags=["admin"])
api_router.include_router(admin_freelance.router, prefix="/admin", tags=["admin"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])
api_router.include_router(reports.admin_router, prefix="/admin", tags=["admin"])
api_router.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
api_router.include_router(billing.router, prefix="/billing", tags=["billing"])
api_router.include_router(stripe_webhook.router, prefix="/stripe", tags=["stripe"])
