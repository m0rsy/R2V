from __future__ import annotations

"""Startup bootstrap helpers.

Seeds the owner-level super admin from configuration. This is intentionally the
only path that can mint a super_admin: there is no public signup for it.
"""

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import get_logger
from app.core.permissions import ROLE_SUPER_ADMIN
from app.core.security import hash_password
from app.db.models.user import User, UserProfile

log = get_logger(__name__)


def seed_super_admin(db: Session) -> None:
    """Create or promote the configured super admin account.

    Idempotent: safe to run on every startup. If the account exists it is
    promoted to super_admin (and reactivated); the password is only set when
    creating a brand new account.
    """
    email = (settings.super_admin_email or "").strip().lower()
    if not email:
        return

    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()

    if user:
        changed = False
        if user.role != ROLE_SUPER_ADMIN:
            user.role = ROLE_SUPER_ADMIN
            changed = True
        if not user.is_active:
            user.is_active = True
            changed = True
        if not user.email_verified:
            user.email_verified = True
            user.email_verified_at = dt.datetime.now(dt.timezone.utc)
            changed = True
        if changed:
            db.commit()
            log.info("super_admin_promoted", extra={"email": email})
        return

    password = settings.super_admin_password
    if not password:
        log.warning(
            "super_admin_seed_skipped_no_password",
            extra={"email": email},
        )
        return

    base_username = (settings.super_admin_username or email.split("@")[0]).strip()
    username = base_username or "owner"
    suffix = 1
    while db.execute(
        select(UserProfile).where(UserProfile.username == username)
    ).scalar_one_or_none():
        suffix += 1
        username = f"{base_username}{suffix}"

    user = User(
        email=email,
        password_hash=hash_password(password),
        role=ROLE_SUPER_ADMIN,
        is_active=True,
        email_verified=True,
        email_verified_at=dt.datetime.now(dt.timezone.utc),
        primary_auth_provider="password",
    )
    user.profile = UserProfile(username=username, bio=None, avatar_url=None, links=None)
    db.add(user)
    db.commit()
    log.info("super_admin_created", extra={"email": email, "username": username})
