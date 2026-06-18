from __future__ import annotations

"""End-to-end tests for the email-verification + Google verified-login flow."""

import uuid

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.api.routers.auth import _get_or_create_oauth_user
from app.core.security import hash_password
from app.db.models.oauth_account import OAuthAccount
from app.db.models.user import User, UserProfile


def _unique():
    tag = uuid.uuid4().hex[:12]
    return f"verify_{tag}@example.com", f"verify_{tag}"


def _signup(client, email, username, password="password123"):
    return client.post(
        "/auth/signup",
        json={"email": email, "password": password, "username": username},
    )


def test_signup_creates_unverified_user(client, db_session):
    email, username = _unique()
    res = _signup(client, email, username)

    assert res.status_code == 200, res.text
    body = res.json()
    assert body["requires_verification"] is True
    assert body["email"] == email
    # Signup must NOT log the user in.
    assert "access_token" not in body
    # Dev env returns the code for testing.
    assert body.get("dev_code")

    user = db_session.execute(select(User).where(User.email == email)).scalar_one()
    assert user.email_verified is False
    assert user.email_verified_at is None


def test_login_rejects_unverified_password_user(client):
    email, username = _unique()
    _signup(client, email, username)

    res = client.post("/auth/login", json={"email": email, "password": "password123"})
    assert res.status_code == 403
    assert res.json()["detail"] == "EMAIL_NOT_VERIFIED"


def test_verify_confirm_sets_verified_and_returns_tokens(client, db_session):
    email, username = _unique()
    dev_code = _signup(client, email, username).json()["dev_code"]

    res = client.post("/auth/verify/confirm", json={"email": email, "code": dev_code})
    assert res.status_code == 200, res.text
    tokens = res.json()
    assert tokens["access_token"]
    assert tokens["refresh_token"]

    db_session.expire_all()
    user = db_session.execute(select(User).where(User.email == email)).scalar_one()
    assert user.email_verified is True
    assert user.email_verified_at is not None

    # Login now succeeds and the access token unlocks a protected endpoint.
    login = client.post("/auth/login", json={"email": email, "password": "password123"})
    assert login.status_code == 200, login.text

    me = client.get("/me", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    assert me.status_code == 200, me.text
    assert me.json()["email_verified"] is True


def test_google_oauth_creates_verified_user(db_session):
    email, _ = _unique()
    claims = {"sub": f"google-{uuid.uuid4().hex}", "email": email, "email_verified": True}

    user = _get_or_create_oauth_user(db_session, "google", claims)

    assert user.email == email
    assert user.email_verified is True
    assert user.email_verified_at is not None
    assert user.primary_auth_provider == "google"

    account = db_session.execute(
        select(OAuthAccount).where(OAuthAccount.subject == claims["sub"])
    ).scalar_one()
    assert account.user_id == user.id


def test_google_oauth_rejects_unverified_email(db_session):
    email, _ = _unique()
    claims = {"sub": f"google-{uuid.uuid4().hex}", "email": email, "email_verified": False}

    with pytest.raises(HTTPException) as exc:
        _get_or_create_oauth_user(db_session, "google", claims)
    assert exc.value.status_code == 400
    assert exc.value.detail == "EMAIL_NOT_VERIFIED"

    # No user should have been created for the rejected login.
    assert db_session.execute(select(User).where(User.email == email)).scalar_one_or_none() is None


def test_google_oauth_links_existing_password_user(db_session):
    email, username = _unique()
    existing = User(
        email=email,
        password_hash=hash_password("password123"),
        role="user",
        is_active=True,
        email_verified=False,
        primary_auth_provider="password",
    )
    existing.profile = UserProfile(username=username, bio=None, avatar_url=None, links=None)
    db_session.add(existing)
    db_session.flush()
    existing_id = existing.id

    claims = {"sub": f"google-{uuid.uuid4().hex}", "email": email, "email_verified": True}
    linked = _get_or_create_oauth_user(db_session, "google", claims)

    # Same account, not a duplicate.
    assert linked.id == existing_id
    users = db_session.execute(select(User).where(User.email == email)).scalars().all()
    assert len(users) == 1
    # Google login confirms the email.
    assert linked.email_verified is True
    account = db_session.execute(
        select(OAuthAccount).where(OAuthAccount.subject == claims["sub"])
    ).scalar_one()
    assert account.user_id == existing_id
