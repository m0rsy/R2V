"""add verification codes table

Revision ID: 0002_verification_codes
Revises: 0001_initial
Create Date: 2025-02-14 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "0002_verification_codes"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "verification_codes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_verification_codes_user_id", "verification_codes", ["user_id"])
    op.create_index("ix_verification_codes_email", "verification_codes", ["email"])
    op.create_index("ix_verification_codes_purpose", "verification_codes", ["purpose"])
    op.create_index("ix_verification_codes_code_hash", "verification_codes", ["code_hash"])
    op.create_index("ix_verification_codes_token_hash", "verification_codes", ["token_hash"])


def downgrade() -> None:
    op.drop_index("ix_verification_codes_token_hash", table_name="verification_codes")
    op.drop_index("ix_verification_codes_code_hash", table_name="verification_codes")
    op.drop_index("ix_verification_codes_purpose", table_name="verification_codes")
    op.drop_index("ix_verification_codes_email", table_name="verification_codes")
    op.drop_index("ix_verification_codes_user_id", table_name="verification_codes")
    op.drop_table("verification_codes")
