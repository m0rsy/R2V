from __future__ import annotations

import time
import uuid
import re
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import settings
from app.core.logging import configure_logging, get_logger
from app.core.rate_limit import rate_limit_middleware
from app.api.router import api_router

configure_logging()
log = get_logger(__name__)

class NormalizePathMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] in {"http", "websocket"}:
            path = scope.get("path", "")
            if "//" in path:
                normalized = re.sub(r"/+", "/", path)
                scope = dict(scope)
                scope["path"] = normalized
                if "raw_path" in scope:
                    scope["raw_path"] = normalized.encode()
        await self.app(scope, receive, send)

class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
        request.state.request_id = request_id
        start = time.time()
        response = await call_next(request)
        response.headers["x-request-id"] = request_id
        duration_ms = int((time.time() - start) * 1000)
        log.info(
            "request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "duration_ms": duration_ms,
            },
        )
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Loud warning for a misconfiguration that silently breaks signup: email is
    # required to verify but no email transport is enabled, so users can never
    # receive their code. (Harmless when REQUIRE_EMAIL_VERIFICATION=false.)
    if (
        settings.require_email_verification
        and not settings.email_enabled
        and settings.is_production
    ):
        log.warning(
            "EMAIL_DISABLED_BUT_VERIFICATION_REQUIRED: REQUIRE_EMAIL_VERIFICATION=true "
            "but EMAIL_ENABLED=false in production -- users cannot receive "
            "verification codes. Enable SMTP (EMAIL_ENABLED=true) or set "
            "REQUIRE_EMAIL_VERIFICATION=false."
        )

    # No demo/sample data is seeded on startup. The platform shows real data
    # from the database, or polished empty states when it is empty.
    # The only seed is the owner-level super admin, when configured.
    try:
        from app.db.session import SessionLocal
        from app.services.bootstrap import seed_super_admin

        db = SessionLocal()
        try:
            seed_super_admin(db)
        finally:
            db.close()
    except Exception:  # pragma: no cover - never block startup on seeding
        log.warning("super_admin_seed_failed", exc_info=True)
    yield


app = FastAPI(
    title="R2V Studio Backend",
    version="0.1.0",
    default_response_class=ORJSONResponse,
    lifespan=lifespan,
)

# Middleware registration: last-added is outermost (processed first on incoming requests).
# Order: NormalizePathMiddleware (innermost) → RequestIDMiddleware → rate_limit → CORSMiddleware (outermost).
# CORSMiddleware must be outermost so that 4xx/5xx responses from inner layers still carry CORS headers.
app.add_middleware(NormalizePathMiddleware)
app.add_middleware(RequestIDMiddleware)
app.add_middleware(BaseHTTPMiddleware, dispatch=rate_limit_middleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.allowed_origins.split(",") if o.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_origin_regex=settings.allowed_origin_regex,
)

app.include_router(api_router)

@app.get("/health")
async def health():
    return {"ok": True, "env": settings.env}
