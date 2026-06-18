"""Live System Health checks for the admin dashboard.

Every check is read-only and defensively wrapped: a single failing probe must
never 500 the admin page — it degrades to a status string + a warning instead.
The response intentionally contains only statuses, latencies, counts and
booleans — never env values, secrets, tokens or presigned URLs.
"""

from __future__ import annotations

import datetime as dt
import time

import httpx
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.services.redis_client import get_redis_sync
from app.services.s3 import s3

# Wall-clock + monotonic process start, captured at import (≈ API start).
_STARTED_AT = dt.datetime.now(dt.timezone.utc)
_STARTED_MONO = time.monotonic()

# Celery's broker queue is a Redis list keyed by the queue name (see
# celery_app.conf.task_default_queue = "r2v").
_CELERY_QUEUE_KEY = "r2v"

# Cap object enumeration so storage sizing stays cheap on large buckets.
_STORAGE_MAX_OBJECTS = 50_000


def _ms(start: float) -> float:
    return round((time.perf_counter() - start) * 1000, 1)


def _human_bytes(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def check_backend() -> dict:
    return {
        "status": "connected",
        "version": "0.1.0",
        "uptime_seconds": int(time.monotonic() - _STARTED_MONO),
    }


def check_database(db: Session) -> tuple[dict, list[str]]:
    warnings: list[str] = []
    start = time.perf_counter()
    try:
        db.execute(text("SELECT 1"))
        return {"status": "connected", "latency_ms": _ms(start)}, warnings
    except Exception:
        warnings.append("Database is not responding.")
        return {"status": "down", "latency_ms": None}, warnings


def check_redis() -> tuple[dict, list[str]]:
    warnings: list[str] = []
    start = time.perf_counter()
    try:
        r = get_redis_sync()
        r.ping()
        latency = _ms(start)
        try:
            queue_size = int(r.llen(_CELERY_QUEUE_KEY))
        except Exception:
            queue_size = None
        return {"status": "connected", "latency_ms": latency, "queue_size": queue_size}, warnings
    except Exception:
        warnings.append("Redis broker is not responding.")
        return {"status": "down", "latency_ms": None, "queue_size": None}, warnings


def check_celery(redis_queue_size: int | None) -> tuple[dict, list[str]]:
    """Inspect Celery workers over the broker. This can be slow/unreliable in
    containerised setups, so it uses a short timeout and degrades gracefully —
    the real Redis queue length is always surfaced regardless."""
    warnings: list[str] = []
    result = {
        "status": "unknown",
        "workers_online": 0,
        "queue_size": redis_queue_size if redis_queue_size is not None else 0,
        "active_tasks": 0,
        "reserved_tasks": 0,
    }
    try:
        # Imported lazily so a worker/celery import issue can't break the API.
        from app.workers.celery_app import celery_app

        inspect = celery_app.control.inspect(timeout=1.0)
        ping = inspect.ping() or {}
        result["workers_online"] = len(ping)
        if ping:
            active = inspect.active() or {}
            reserved = inspect.reserved() or {}
            result["active_tasks"] = sum(len(v) for v in active.values())
            result["reserved_tasks"] = sum(len(v) for v in reserved.values())
            result["status"] = "connected"
        else:
            result["status"] = "degraded"
            warnings.append("No Celery workers responded to ping.")
    except Exception:
        result["status"] = "unknown"
        warnings.append("Could not inspect Celery workers.")
    return result, warnings


def check_storage() -> tuple[dict, list[str]]:
    warnings: list[str] = []
    bucket_map = {
        "job_outputs": settings.s3_bucket_job_outputs,
        "marketplace_models": settings.s3_bucket_marketplace_models,
        "marketplace_thumbs": settings.s3_bucket_marketplace_thumbs,
    }
    provider = "minio" if settings.s3_endpoint_url else "s3"
    buckets: dict[str, bool] = {}
    used_bytes = 0
    estimated = False
    any_ok = False

    client = s3.client
    for label, name in bucket_map.items():
        try:
            client.head_bucket(Bucket=name)
            buckets[label] = True
            any_ok = True
        except Exception:
            buckets[label] = False
            warnings.append(f"Storage bucket '{label}' is unreachable.")
            continue
        # Sum object sizes, capped so large buckets stay cheap.
        try:
            counted = 0
            paginator = client.get_paginator("list_objects_v2")
            for page in paginator.paginate(Bucket=name):
                for obj in page.get("Contents", []) or []:
                    used_bytes += int(obj.get("Size", 0) or 0)
                    counted += 1
                if counted >= _STORAGE_MAX_OBJECTS:
                    estimated = True
                    break
        except Exception:
            # Sizing is best-effort; bucket reachability already recorded.
            pass

    if any_ok:
        status = "connected" if all(buckets.values()) else "degraded"
    else:
        status = "down"

    return {
        "status": status,
        "provider": provider,
        "buckets": buckets,
        "used_bytes": used_bytes,
        "used_label": _human_bytes(used_bytes) + (" (≈)" if estimated else ""),
        "estimated": estimated,
    }, warnings


def check_ai_pipeline() -> tuple[dict, list[str]]:
    warnings: list[str] = []
    endpoint = settings.modal_endpoint_url
    configured = bool(endpoint)

    modal: dict = {"status": "not_configured", "latency_ms": None}
    if not configured:
        warnings.append("Modal AI endpoint is not configured.")
    else:
        start = time.perf_counter()
        try:
            with httpx.Client(timeout=3.0, follow_redirects=True) as client:
                resp = client.get(endpoint.rstrip("/") + "/health")
            if resp.status_code < 500:
                modal = {"status": "reachable", "latency_ms": _ms(start)}
            else:
                modal = {"status": "unreachable", "latency_ms": _ms(start)}
                warnings.append("Modal AI endpoint returned a server error.")
        except Exception:
            modal = {"status": "unreachable", "latency_ms": None}
            warnings.append("Modal AI endpoint is unreachable.")

    # Stable Diffusion / Hunyuan3D / Gemini are all served by the Modal endpoint;
    # there are no separate credentials, so the honest status is whether the
    # Modal pipeline is configured.
    engine = "configured" if configured else "not_configured"
    return {
        "modal_endpoint": modal,
        "stable_diffusion": {"status": engine},
        "hunyuan3d": {"status": engine},
        "gemini": {"status": engine},
    }, warnings


def check_marketplace_moderation() -> tuple[dict, list[str]]:
    # No automated moderation service/config exists in this deployment. Report
    # honestly rather than faking a "connected" status.
    return (
        {"status": "not_configured"},
        ["Marketplace moderation is not configured."],
    )


def collect_system_health(db: Session) -> dict:
    warnings: list[str] = []

    backend = check_backend()
    database, w = check_database(db)
    warnings += w
    redis_info, w = check_redis()
    warnings += w
    celery, w = check_celery(redis_info.get("queue_size"))
    warnings += w
    storage, w = check_storage()
    warnings += w
    ai_pipeline, w = check_ai_pipeline()
    warnings += w
    moderation, w = check_marketplace_moderation()
    warnings += w

    ok = (
        database["status"] == "connected"
        and redis_info["status"] == "connected"
        and storage["status"] != "down"
    )

    return {
        "ok": ok,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "backend": backend,
        "database": database,
        "redis": redis_info,
        "celery": celery,
        "storage": storage,
        "ai_pipeline": ai_pipeline,
        "marketplace_moderation": moderation,
        "warnings": warnings,
    }
