from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import select
from app.api.deps import get_db, get_current_user
from app.api.schemas.me import MeOut, MeUpdateIn
from app.core.errors import conflict
from app.core.permissions import permissions_for_role
from app.db.models.user import UserProfile

router = APIRouter()

@router.get("/me", response_model=MeOut)
def get_me(user = Depends(get_current_user)):
    profile = user.profile
    return MeOut(
        id=str(user.id),
        email=user.email,
        role=user.role,
        username=profile.username if profile else "",
        bio=profile.bio if profile else None,
        avatar_url=profile.avatar_url if profile else None,
        links=profile.links if profile else None,
        is_active=user.is_active,
        email_verified=user.email_verified,
        permissions=permissions_for_role(user.role),
    )

@router.patch("/me", response_model=MeOut)
def update_me(payload: MeUpdateIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    profile = user.profile
    if not profile:
        profile = UserProfile(user_id=user.id, username=payload.username or user.email.split("@")[0])
        db.add(profile)
    if payload.username and payload.username != profile.username:
        exists = db.execute(select(UserProfile).where(UserProfile.username == payload.username)).scalar_one_or_none()
        if exists:
            conflict("Username already taken")
        profile.username = payload.username
    if payload.bio is not None:
        profile.bio = payload.bio
    if payload.avatar_url is not None:
        profile.avatar_url = payload.avatar_url
    if payload.links is not None:
        profile.links = payload.links
    db.commit(); db.refresh(user)
    return get_me(user)

@router.delete("/me")
def delete_me(db: Session = Depends(get_db), user = Depends(get_current_user)):
    db.delete(user)
    db.commit()
    return {"detail": "ok"}
