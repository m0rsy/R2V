from __future__ import annotations
from celery import Celery
from app.core.config import settings

celery_app = Celery(
    "r2v",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=["app.workers.tasks"],
)
celery_app.conf.task_default_queue = "r2v"
celery_app.conf.task_routes = {"app.workers.tasks.*": {"queue": "r2v"}}
celery_app.conf.worker_prefetch_multiplier = 1
celery_app.conf.task_acks_late = True
