"""chat attachments, voice notes, message types, conversation kind

Revision ID: 0006_chat_attachments
Revises: 0005_reports
Create Date: 2026-06-08 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "0006_chat_attachments"
down_revision = "0005_reports"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ------------------------------------------------------------------ #
    # Conversation.kind: "direct" (mutual-follow gated) vs "freelance".
    # ------------------------------------------------------------------ #
    op.add_column(
        "conversations",
        sa.Column("kind", sa.String(length=32), nullable=False, server_default="direct"),
    )

    # ------------------------------------------------------------------ #
    # Message: type + nullable body (attachment-only / voice-only messages).
    # ------------------------------------------------------------------ #
    op.add_column(
        "chat_messages",
        sa.Column("message_type", sa.String(length=16), nullable=False, server_default="text"),
    )
    op.alter_column("chat_messages", "body", existing_type=sa.Text(), nullable=True)

    # ------------------------------------------------------------------ #
    # Attachments (images / documents / voice / 3D models / other).
    # ------------------------------------------------------------------ #
    op.create_table(
        "message_attachments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("message_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("file_name", sa.String(length=255), nullable=False),
        sa.Column("mime_type", sa.String(length=128), nullable=False),
        sa.Column("file_size", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("attachment_type", sa.String(length=16), nullable=False, server_default="other"),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["message_id"], ["chat_messages.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_message_attachments_message_id", "message_attachments", ["message_id"])


def downgrade() -> None:
    op.drop_index("ix_message_attachments_message_id", table_name="message_attachments")
    op.drop_table("message_attachments")

    op.alter_column("chat_messages", "body", existing_type=sa.Text(), nullable=False)
    op.drop_column("chat_messages", "message_type")

    op.drop_column("conversations", "kind")
