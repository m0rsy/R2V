from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from uuid import UUID
from sqlalchemy import select, desc, func, or_
from app.api.deps import get_db, get_current_user
from app.api.schemas.social import FollowUserOut, PostCreateIn, PostOut, ProfileOut
from app.core.errors import not_found, conflict
from app.db.models.social import Post, Like, Save, Follow
from app.db.models.marketplace import Asset
from app.db.models.user import User, UserProfile

router = APIRouter()

def to_post_out(p: Post) -> PostOut:
    return PostOut(
        id=str(p.id), creator_id=str(p.creator_id), asset_id=str(p.asset_id) if p.asset_id else None,
        caption=p.caption, media_keys=p.media_keys or [], created_at=p.created_at.isoformat()
    )

@router.post("/posts", response_model=PostOut)
def create_post(payload: PostCreateIn, db: Session = Depends(get_db), user = Depends(get_current_user)):
    p = Post(creator_id=user.id, asset_id=payload.asset_id, caption=payload.caption, media_keys=payload.media_keys)
    db.add(p); db.commit(); db.refresh(p)
    return to_post_out(p)

@router.get("/posts", response_model=list[PostOut])
def feed(limit: int = 20, offset: int = 0, db: Session = Depends(get_db)):
    q = select(Post).order_by(desc(Post.created_at)).limit(limit).offset(offset)
    return [to_post_out(p) for p in db.execute(q).scalars().all()]

@router.post("/posts/{post_id}/like")
def like(post_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    existing = db.execute(select(Like).where(Like.user_id==user.id, Like.post_id==post_id)).scalar_one_or_none()
    if existing:
        conflict("Already liked")
    db.add(Like(user_id=user.id, post_id=post_id))
    db.commit()
    return {"detail": "ok"}

@router.post("/posts/{post_id}/save")
def save(post_id: str, db: Session = Depends(get_db), user = Depends(get_current_user)):
    existing = db.execute(select(Save).where(Save.user_id==user.id, Save.post_id==post_id)).scalar_one_or_none()
    if existing:
        conflict("Already saved")
    db.add(Save(user_id=user.id, post_id=post_id))
    db.commit()
    return {"detail": "ok"}

@router.post("/follow/{user_id}")
def follow(user_id: UUID, db: Session = Depends(get_db), user = Depends(get_current_user)):
    existing = db.execute(select(Follow).where(Follow.follower_id==user.id, Follow.following_id==user_id)).scalar_one_or_none()
    if existing:
        conflict("Already following")
    db.add(Follow(follower_id=user.id, following_id=user_id))
    db.commit()
    return {"detail": "ok"}

@router.delete("/follow/{user_id}")
def unfollow(user_id: UUID, db: Session = Depends(get_db), user = Depends(get_current_user)):
    existing = db.execute(select(Follow).where(Follow.follower_id==user.id, Follow.following_id==user_id)).scalar_one_or_none()
    if not existing:
        not_found("Follow not found")
    db.delete(existing)
    db.commit()
    return {"detail": "ok"}

@router.get("/profile/{user_id}", response_model=ProfileOut)
def profile(user_id: UUID, db: Session = Depends(get_db), user = Depends(get_current_user)):
    prof = db.get(UserProfile, user_id)
    if not prof:
        target_user = db.get(User, user_id)
        if not target_user:
            not_found("Profile not found")
        default_username = target_user.email.split("@")[0]
        prof = UserProfile(user_id=user_id, username=default_username, bio=None, avatar_url=None, links=None)
        db.add(prof)
        db.commit()
        db.refresh(prof)
    posts_stmt = select(func.count()).select_from(Asset).where(Asset.creator_id==user_id)
    if user.id != user_id:
        posts_stmt = posts_stmt.where(Asset.visibility == "published")
    posts = db.execute(posts_stmt).scalar_one()
    followers = db.execute(select(func.count()).select_from(Follow).where(Follow.following_id==user_id)).scalar_one()
    following = db.execute(select(func.count()).select_from(Follow).where(Follow.follower_id==user_id)).scalar_one()
    is_following = False
    is_followed_by = False
    if user.id != user_id:
        is_following = db.execute(
            select(Follow).where(Follow.follower_id==user.id, Follow.following_id==user_id)
        ).scalar_one_or_none() is not None
        is_followed_by = db.execute(
            select(Follow).where(Follow.follower_id==user_id, Follow.following_id==user.id)
        ).scalar_one_or_none() is not None
    return ProfileOut(
        user_id=str(user_id),
        username=prof.username,
        bio=prof.bio,
        avatar_url=prof.avatar_url,
        posts=posts,
        followers=followers,
        following=following,
        is_following=is_following,
        is_followed_by=is_followed_by,
        is_mutual=is_following and is_followed_by,
        is_self=user.id == user_id,
    )

def _follow_user_out(user: User, profile: UserProfile | None) -> FollowUserOut:
    username = profile.username if profile and profile.username else user.email.split("@")[0]
    return FollowUserOut(
        user_id=str(user.id),
        username=username,
        avatar_url=profile.avatar_url if profile else None,
    )

@router.get("/followers/{user_id}", response_model=list[FollowUserOut])
def followers(user_id: UUID, limit: int = 50, offset: int = 0, db: Session = Depends(get_db), user = Depends(get_current_user)):
    stmt = (
        select(User, UserProfile)
        .join(Follow, Follow.follower_id == User.id)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(Follow.following_id == user_id)
        .order_by(UserProfile.username.nullslast(), User.email)
        .limit(limit)
        .offset(offset)
    )
    rows = db.execute(stmt).all()
    return [_follow_user_out(row[0], row[1]) for row in rows]

@router.get("/following/{user_id}", response_model=list[FollowUserOut])
def following(user_id: UUID, limit: int = 50, offset: int = 0, db: Session = Depends(get_db), user = Depends(get_current_user)):
    stmt = (
        select(User, UserProfile)
        .join(Follow, Follow.following_id == User.id)
        .outerjoin(UserProfile, UserProfile.user_id == User.id)
        .where(Follow.follower_id == user_id)
        .order_by(UserProfile.username.nullslast(), User.email)
        .limit(limit)
        .offset(offset)
    )
    rows = db.execute(stmt).all()
    return [_follow_user_out(row[0], row[1]) for row in rows]
