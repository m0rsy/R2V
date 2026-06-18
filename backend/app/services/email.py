"""Outbound email (SMTP) for verification and password-reset codes.

Design notes / safety:
- All sending is gated by ``settings.email_enabled``. When disabled the helpers
  are a no-op so non-prod environments keep working without SMTP credentials.
- The verification/reset code is NEVER logged. Logs only ever contain the
  recipient address and a coarse outcome, so codes cannot leak via logs.
- ``send_*`` raise :class:`EmailSendError` on failure so callers can convert it
  into a safe API error without exposing SMTP internals to the client.
"""
from __future__ import annotations

import smtplib
from email.message import EmailMessage

from app.core.config import settings
from app.core.logging import get_logger

log = get_logger(__name__)


class EmailSendError(Exception):
    """Raised when an email could not be delivered."""


def email_configured() -> bool:
    """True when sending is enabled and the minimum SMTP settings are present."""
    return bool(
        settings.email_enabled
        and settings.smtp_host
        and settings.smtp_from_email
    )


def _from_header() -> str:
    name = settings.smtp_from_name.strip()
    addr = settings.smtp_from_email.strip()
    return f"{name} <{addr}>" if name else addr


def _send(to_email: str, subject: str, body: str) -> None:
    """Deliver one plain-text email. No-op when email is disabled.

    Raises EmailSendError on any SMTP/connection failure. The message body (which
    contains the code) is never logged.
    """
    if not settings.email_enabled:
        # Disabled on purpose: do not attempt delivery. The caller decides
        # whether this is acceptable (e.g. dev, or REQUIRE_EMAIL_VERIFICATION=false).
        log.info("email_skipped_disabled to=%s", to_email)
        return

    if not email_configured():
        log.warning("email_not_configured to=%s", to_email)
        raise EmailSendError("Email service is not configured")

    msg = EmailMessage()
    msg["From"] = _from_header()
    msg["To"] = to_email
    msg["Subject"] = subject
    msg.set_content(body)

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as server:
            if settings.smtp_use_tls:
                server.starttls()
            if settings.smtp_username:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)
    except Exception as exc:  # noqa: BLE001 - normalize to a safe error type
        # Log only the recipient + exception type, never the body/code or
        # credentials.
        log.error("email_send_failed to=%s err=%s", to_email, type(exc).__name__)
        raise EmailSendError("Failed to send email") from exc

    log.info("email_sent to=%s subject=%s", to_email, subject)


def send_verification_code(email: str, code: str) -> None:
    """Email a freshly minted email-verification code."""
    subject = "Your RealTwoVirtual verification code"
    body = (
        "Welcome to RealTwoVirtual!\n\n"
        f"Your verification code is: {code}\n\n"
        f"It expires in {settings.verification_code_expires_min} minutes.\n"
        "If you did not create an account, you can ignore this email."
    )
    _send(email, subject, body)


def send_password_reset_code(email: str, code: str) -> None:
    """Email a password-reset code."""
    subject = "Your RealTwoVirtual password reset code"
    body = (
        "We received a request to reset your RealTwoVirtual password.\n\n"
        f"Your password reset code is: {code}\n\n"
        f"It expires in {settings.password_reset_expires_min} minutes.\n"
        "If you did not request this, you can ignore this email."
    )
    _send(email, subject, body)
