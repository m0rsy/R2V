from __future__ import annotations
import redis
from redis import Redis
from app.core.config import settings

_redis_sync: Redis | None = None

def get_redis_sync() -> Redis:
    global _redis_sync
    if _redis_sync is None:
        _redis_sync = redis.Redis.from_url(settings.redis_url, decode_responses=True)
    return _redis_sync
