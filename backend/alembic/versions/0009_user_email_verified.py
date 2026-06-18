"""add email verification fields to users

Revision ID: 0009_user_email_verified
Revises: 0008_freelance_rebuild
Create Date: 2026-06-14 00:00:00.000000

Non-destructive: only adds columns to the existing ``users`` table. Existing
accounts are grandfathered in as verified so the live auth flow is not broken;
only accounts created after this migration must verify their email.
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "0009_user_email_verified"
down_revision = "0008_freelance_rebuild"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "email_verified",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )
    op.add_column(
        "users",
        sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "primary_auth_provider",
            sa.String(length=32),
            server_default="password",
            nullable=False,
        ),
    )

    # Grandfather every pre-existing account as verified so current users are not
    # locked out. New signups insert email_verified=false explicitly.
    op.execute(
        "UPDATE users SET email_verified = true, email_verified_at = now() "
        "WHERE email_verified = false"
    )


def downgrade() -> None:
    op.drop_column("users", "primary_auth_provider")
    op.drop_column("users", "email_verified_at")
    op.drop_column("users", "email_verified")
