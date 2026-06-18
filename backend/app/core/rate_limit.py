from __future__ import annotations
from fastapi import Request
from starlette.responses import JSONResponse
from app.core.config import settings
from app.services.redis_client import get_redis_sync

async def rate_limit_middleware(request: Request, call_next):
    ip = request.client.host if request.client else "unknown"
    key = f"rl:{ip}:{request.url.path}"
    r = get_redis_sync()
    try:
        count = r.incr(key)
        if count == 1:
            r.expire(key, settings.rate_limit_window_seconds)
        if count > settings.rate_limit_requests:
            retry_after = r.ttl(key)
            return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"}, headers={"Retry-After": str(max(retry_after, 1))})
    except Exception:
        pass
    return await call_next(request)
