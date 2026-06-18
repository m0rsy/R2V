"""add live progress fields (stage, message) to ai_jobs

Revision ID: 0010_ai_job_progress
Revises: 0009_user_email_verified
Create Date: 2026-06-15 00:00:00.000000

Non-destructive: only ADDS two nullable columns to the existing ``ai_jobs``
table so the AI page can show real-time Modal generation progress (stage label
and status message). The ``progress`` integer column already exists from the
initial migration. No data is dropped and old AI jobs keep working — the new
columns are simply NULL for any job created before this migration.
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "0010_ai_job_progress"
down_revision = "0009_user_email_verified"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ai_jobs",
        sa.Column("stage", sa.String(length=64), nullable=True),
    )
    op.add_column(
        "ai_jobs",
        sa.Column("message", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ai_jobs", "message")
    op.drop_column("ai_jobs", "stage")
