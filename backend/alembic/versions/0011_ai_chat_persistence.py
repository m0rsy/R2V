"""persist AI-assistant chat history (ai_conversations, ai_messages)

Revision ID: 0011_ai_chat_persistence
Revises: 0010_ai_job_progress
Create Date: 2026-06-16 00:00:00.000000

Non-destructive: only CREATES two brand-new tables so AI-page chat history
survives logout/login and page reloads. It does NOT touch, drop, rename, or
alter any existing table (the peer-to-peer DM tables ``conversations`` /
``chat_messages`` are unrelated and left exactly as-is). Both tables are scoped
by ``user_id`` via a CASCADE FK to ``users`` so a user only ever sees their own
threads, and deleting a user cleans up their AI chats automatically.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "0011_ai_chat_persistence"
down_revision = "0010_ai_job_progress"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=200), nullable=True),
        sa.Column("last_job_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_ai_conversations_user_id", "ai_conversations", ["user_id"])
    op.create_index(
        "ix_ai_conversations_user_updated", "ai_conversations", ["user_id", "updated_at"]
    )

    op.create_table(
        "ai_messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "conversation_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("ai_conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("role", sa.String(length=16), nullable=False, server_default="user"),
        sa.Column("text", sa.Text(), nullable=True),
        sa.Column("model_url", sa.Text(), nullable=True),
        sa.Column("job_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "meta",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_ai_messages_conversation_id", "ai_messages", ["conversation_id"])
    op.create_index("ix_ai_messages_created_at", "ai_messages", ["created_at"])
    op.create_index(
        "ix_ai_messages_conv_created", "ai_messages", ["conversation_id", "created_at"]
    )


def downgrade() -> None:
    # Provided for completeness only. Per project policy, downgrade is NOT run in
    # production (it would drop AI chat history).
    op.drop_index("ix_ai_messages_conv_created", table_name="ai_messages")
    op.drop_index("ix_ai_messages_created_at", table_name="ai_messages")
    op.drop_index("ix_ai_messages_conversation_id", table_name="ai_messages")
    op.drop_table("ai_messages")
    op.drop_index("ix_ai_conversations_user_updated", table_name="ai_conversations")
    op.drop_index("ix_ai_conversations_user_id", table_name="ai_conversations")
    op.drop_table("ai_conversations")
