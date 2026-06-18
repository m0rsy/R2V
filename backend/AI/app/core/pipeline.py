#pipeline.py
from __future__ import annotations

import os
import threading
from typing import Any, Dict, Optional

_lock = threading.Lock()
_pipelines: Optional[Dict[str, Any]] = None
_loading_error: Optional[BaseException] = None


def init_pipelines(cache_dir: Optional[str] = None) -> Dict[str, Any]:
    """
    Load all AI pipelines once per process (thread-safe double-checked locking).

    cache_dir:
      Path to your local HuggingFace model cache.
      Example: "D:/Grademodels/model_cache"
      If omitted, falls back to HF_HOME env var.
    """
    global _pipelines, _loading_error

    # Fast path — already loaded
    if _pipelines is not None:
        return _pipelines
    if _loading_error is not None:
        raise RuntimeError(f"Pipeline load previously failed: {_loading_error}") from _loading_error

    with _lock:
        # Re-check inside the lock
        if _pipelines is not None:
            return _pipelines
        if _loading_error is not None:
            raise RuntimeError(f"Pipeline load previously failed: {_loading_error}") from _loading_error

        try:
            from app.core.loader import load_all_pipelines

            # Defensively set HF_HOME so any lib that reads it gets the right path
            if cache_dir:
                os.environ.setdefault("HF_HOME", cache_dir)

            _pipelines = load_all_pipelines(cache_dir=cache_dir)
            return _pipelines

        except BaseException as exc:
            _loading_error = exc
            _pipelines = None
            raise


def get_pipelines(cache_dir: Optional[str] = None) -> Dict[str, Any]:
    """
    Returns loaded pipelines. Calls init_pipelines if not yet loaded.
    Raises RuntimeError if pipelines failed to load.
    """
    return init_pipelines(cache_dir=cache_dir)


def is_ready() -> bool:
    """True only when pipelines are fully loaded with no errors."""
    return _pipelines is not None and _loading_error is None


def reset_pipelines() -> None:
    """
    Force-reset pipeline state (useful for testing or hot-reload scenarios).
    WARNING: Does NOT unload GPU memory. Use with care.
    """
    global _pipelines, _loading_error
    with _lock:
        _pipelines = None
        _loading_error = None