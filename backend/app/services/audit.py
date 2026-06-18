from __future__ import annotations

"""Lightweight audit logging helper.

Records administrative actions to the ``audit_logs`` table. Failures here must
never break the primary request, so callers may rely on this being best-effort.
"""

import uuid

from sqlalchemy.orm import Session

from app.db.models.audit import AuditLog


def log_action(
    db: Session,
    *,
    actor_id: uuid.UUID | str | None,
    action: str,
    entity: str,
    entity_id: str | None = None,
    meta: dict | None = None,
) -> None:
    """Append an audit log row. Does not commit; the caller commits."""
    if isinstance(actor_id, str):
        try:
            actor_id = uuid.UUID(actor_id)
        except ValueError:
            actor_id = None
    db.add(
        AuditLog(
            actor_id=actor_id,
            action=action,
            entity=entity,
            entity_id=str(entity_id) if entity_id is not None else None,
            meta_json=meta or {},
        )
    )
