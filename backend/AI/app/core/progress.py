from __future__ import annotations

from threading import Lock
from typing import Any, Dict, Optional
import time

_lock = Lock()
_store: Dict[str, Dict[str, Any]] = {}


def _now() -> float:
    return time.time()


def _default_job(job_id: str) -> Dict[str, Any]:
    return {
        "job_id": job_id,
        "status": "queued",
        "stage": "queued",
        "percent": 0,
        "message": "",
        "error": None,
        "created_at": _now(),
        "updated_at": _now(),
        "image_url": None,
        "model_glb_url": None,
        "texture_url": None,
        "voice_detected_language": None,
        "voice_transcript_original": None,
        "voice_text_english": None,
        "voice_prompt_used": None,
        "refined_prompt_positive": None,
        "refined_prompt_negative": None,
        "timings": {},
        "settings": {},
        "warnings": [],
    }


def init_job(job_id: str) -> None:
    with _lock:
        _store[job_id] = _default_job(job_id)


def update_job(job_id: str, **fields: Any) -> None:
    with _lock:
        if job_id not in _store:
            _store[job_id] = _default_job(job_id)
        _store[job_id].update(fields)
        _store[job_id]["updated_at"] = _now()


def add_timing(job_id: str, name: str, seconds: float) -> None:
    with _lock:
        if job_id not in _store:
            _store[job_id] = _default_job(job_id)

        timings = dict(_store[job_id].get("timings") or {})
        timings[name] = round(float(seconds), 2)

        _store[job_id]["timings"] = timings
        _store[job_id]["updated_at"] = _now()


def add_warning(job_id: str, warning: str) -> None:
    with _lock:
        if job_id not in _store:
            _store[job_id] = _default_job(job_id)

        warnings = list(_store[job_id].get("warnings") or [])
        warnings.append(warning)

        _store[job_id]["warnings"] = warnings
        _store[job_id]["updated_at"] = _now()


def set_error(job_id: str, err: str) -> None:
    update_job(
        job_id,
        status="error",
        stage="error",
        percent=100,
        error=err,
        message=f"Failed: {err[:120]}",
    )


def set_done(
    job_id: str,
    image_url: str,
    model_glb_url: str,
    texture_url: Optional[str] = None,
) -> None:
    update_job(
        job_id,
        status="done",
        stage="done",
        percent=100,
        message="Completed",
        image_url=image_url,
        model_glb_url=model_glb_url,
        texture_url=texture_url,
        error=None,
    )


def get_job(job_id: str) -> Optional[Dict[str, Any]]:
    with _lock:
        entry = _store.get(job_id)
        return dict(entry) if entry is not None else None


def list_jobs() -> list[Dict[str, Any]]:
    with _lock:
        jobs = [dict(v) for v in _store.values()]
    jobs.sort(key=lambda j: j.get("created_at", 0), reverse=True)
    return jobs


def cleanup_old_jobs(max_age_seconds: float = 3600.0) -> int:
    cutoff = _now() - max_age_seconds
    removed = 0

    with _lock:
        to_del = [
            jid for jid, v in _store.items()
            if v.get("created_at", 0) < cutoff
        ]

        for jid in to_del:
            del _store[jid]
            removed += 1

    return removed