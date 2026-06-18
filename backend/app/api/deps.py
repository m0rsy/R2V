from __future__ import annotations
from typing import Callable, Generator
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session
from app.core.errors import unauthorized, forbidden
from app.core.permissions import (
    ADMIN_ROLES,
    ROLE_SUPER_ADMIN,
    role_has_permission,
)
from app.core.security import decode_token
from app.db.session import SessionLocal
from app.db.models.user import User

bearer = HTTPBearer(auto_error=False)

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if not creds:
        unauthorized("Missing bearer token")
    try:
        payload = decode_token(creds.credentials)
    except Exception:
        unauthorized("Invalid token")
    if payload.get("type") != "access":
        unauthorized("Invalid token type")
    user_id = payload.get("sub")
    user = db.get(User, user_id)
    if not user or not user.is_active:
        unauthorized("User inactive")
    # Gate unverified accounts out of every protected endpoint. Admin roles are
    # exempt (they are seeded verified and must keep working regardless).
    if not user.email_verified and user.role not in ADMIN_ROLES:
        forbidden("EMAIL_NOT_VERIFIED")
    user._jwt_role = payload.get("role")  # type: ignore[attr-defined]
    return user


def get_current_user_optional(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User | None:
    """Like ``get_current_user`` but never raises: returns the authenticated
    user when a valid access token is present, otherwise ``None``. Used by
    public endpoints (e.g. the marketplace listing) that must stay browsable
    anonymously while still returning per-user state (liked/saved) when signed
    in. Mirrors the same inactive/unverified gating so an unverified or disabled
    account is treated as anonymous rather than authenticated."""
    if not creds:
        return None
    try:
        payload = decode_token(creds.credentials)
    except Exception:
        return None
    if payload.get("type") != "access":
        return None
    user = db.get(User, payload.get("sub"))
    if not user or not user.is_active:
        return None
    if not user.email_verified and user.role not in ADMIN_ROLES:
        return None
    user._jwt_role = payload.get("role")  # type: ignore[attr-defined]
    return user


def get_verified_current_user(user: User = Depends(get_current_user)) -> User:
    """Explicit alias for the verified-user dependency. ``get_current_user``
    already rejects unverified non-admin accounts; this name documents intent
    for endpoints that specifically require a verified email."""
    return user

def require_admin(user: User = Depends(get_current_user)) -> User:
    # Authorization uses the live DB role (not the JWT claim) so that promotions
    # and demotions take effect immediately, without waiting for a token refresh.
    if user.role not in ADMIN_ROLES:
        forbidden("Admin access required")
    return user


def require_super_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != ROLE_SUPER_ADMIN:
        forbidden("Super admin access required")
    return user


def require_permission(permission: str) -> Callable[[User], User]:
    """Dependency factory enforcing a single named permission.

    Permissions are derived from the live DB role, so changes apply instantly.
    """

    def _dependency(user: User = Depends(get_current_user)) -> User:
        if not role_has_permission(user.role, permission):
            forbidden(f"Missing permission: {permission}")
        return user

    return _dependency
