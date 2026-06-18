from __future__ import annotations
from pydantic import BaseModel, EmailStr, Field

class SignupIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    username: str = Field(min_length=3, max_length=50)

class LoginIn(BaseModel):
    email: EmailStr
    password: str

class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class SignupOut(BaseModel):
    """Signup result.

    When email verification is required, the user is NOT logged in: the frontend
    routes to the verification screen and ``dev_code`` is only populated when
    ``settings.env == "dev"``.

    When ``REQUIRE_EMAIL_VERIFICATION=false`` the account is created already
    verified and ``access_token``/``refresh_token`` are returned so the frontend
    can enter the app directly."""
    detail: str = "verification_required"
    email: EmailStr
    requires_verification: bool = True
    dev_code: str | None = None
    access_token: str | None = None
    refresh_token: str | None = None
    token_type: str | None = None

class RefreshIn(BaseModel):
    refresh_token: str

class EmailIn(BaseModel):
    email: EmailStr

class VerifyCodeIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=8)

class VerificationOut(BaseModel):
    detail: str = "ok"
    dev_code: str | None = None

class PasswordResetVerifyOut(BaseModel):
    reset_token: str

class PasswordResetIn(BaseModel):
    reset_token: str
    new_password: str = Field(min_length=8, max_length=128)

class ChangePasswordIn(BaseModel):
    new_password: str = Field(min_length=8, max_length=128)


class OAuthStartOut(BaseModel):
    authorization_url: str


class OAuthTokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
