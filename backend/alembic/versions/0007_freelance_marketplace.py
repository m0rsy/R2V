"""freelance marketplace: profiles, projects, proposals, orders, milestones,
deliverables, reviews, favorites, and freelance-only chat.

Revision ID: 0007_freelance_marketplace
Revises: 0006_chat_attachments
Create Date: 2026-06-09 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "0007_freelance_marketplace"
down_revision = "0006_chat_attachments"
branch_labels = None
depends_on = None


def _uuid():
    return postgresql.UUID(as_uuid=True)


def upgrade() -> None:
    # ----------------------------- profiles ----------------------------- #
    op.create_table(
        "freelancer_profiles",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("user_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(length=140), nullable=False),
        sa.Column("bio", sa.Text(), nullable=True),
        sa.Column("category", sa.String(length=80), nullable=True),
        sa.Column("skills", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("portfolio", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("hourly_rate", sa.Numeric(12, 2), nullable=True),
        sa.Column("starting_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("experience_level", sa.String(length=40), nullable=True),
        sa.Column("availability", sa.String(length=40), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="approved"),
        sa.Column("featured", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("rating_avg", sa.Numeric(3, 2), nullable=False, server_default="0"),
        sa.Column("reviews_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("completed_jobs_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", name="uq_freelancer_profile_user"),
    )
    op.create_index("ix_freelancer_profiles_status", "freelancer_profiles", ["status"])
    op.create_index("ix_freelancer_profiles_category", "freelancer_profiles", ["category"])

    # ----------------------------- projects ----------------------------- #
    op.create_table(
        "freelance_projects",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("client_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("category", sa.String(length=80), nullable=True),
        sa.Column("skills", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("attachments", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("budget_type", sa.String(length=16), nullable=False, server_default="fixed"),
        sa.Column("budget_min", sa.Numeric(12, 2), nullable=True),
        sa.Column("budget_max", sa.Numeric(12, 2), nullable=True),
        sa.Column("deadline", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="open"),
        sa.Column("proposals_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_projects_status", "freelance_projects", ["status"])
    op.create_index("ix_freelance_projects_client", "freelance_projects", ["client_id"])
    op.create_index("ix_freelance_projects_category", "freelance_projects", ["category"])
    op.create_index("ix_freelance_projects_created_at", "freelance_projects", ["created_at"])

    # ----------------------------- proposals ---------------------------- #
    op.create_table(
        "freelance_proposals",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("project_id", _uuid(), nullable=False),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("cover_letter", sa.Text(), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("delivery_days", sa.Integer(), nullable=False, server_default="7"),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["project_id"], ["freelance_projects.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freelancer_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("project_id", "freelancer_id", name="uq_proposal_project_freelancer"),
    )
    op.create_index("ix_freelance_proposals_status", "freelance_proposals", ["status"])
    op.create_index("ix_freelance_proposals_freelancer", "freelance_proposals", ["freelancer_id"])
    op.create_index("ix_freelance_proposals_created_at", "freelance_proposals", ["created_at"])

    # ------------------------------ orders ------------------------------ #
    op.create_table(
        "freelance_orders",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("project_id", _uuid(), nullable=True),
        sa.Column("proposal_id", _uuid(), nullable=True),
        sa.Column("client_id", _uuid(), nullable=False),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("deadline", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
        sa.Column("payment_status", sa.String(length=16), nullable=False, server_default="unpaid"),
        sa.Column("dispute_reason", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["project_id"], ["freelance_projects.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["proposal_id"], ["freelance_proposals.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freelancer_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_orders_status", "freelance_orders", ["status"])
    op.create_index("ix_freelance_orders_client", "freelance_orders", ["client_id"])
    op.create_index("ix_freelance_orders_freelancer", "freelance_orders", ["freelancer_id"])
    op.create_index("ix_freelance_orders_created_at", "freelance_orders", ["created_at"])

    # ---------------------------- milestones ---------------------------- #
    op.create_table(
        "freelance_milestones",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("order_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("due_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["order_id"], ["freelance_orders.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_milestones_order", "freelance_milestones", ["order_id"])

    # --------------------------- deliverables --------------------------- #
    op.create_table(
        "freelance_deliverables",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("order_id", _uuid(), nullable=False),
        sa.Column("milestone_id", _uuid(), nullable=True),
        sa.Column("submitted_by", _uuid(), nullable=False),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("files", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="submitted"),
        sa.Column("review_note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["order_id"], ["freelance_orders.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["milestone_id"], ["freelance_milestones.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["submitted_by"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_deliverables_order", "freelance_deliverables", ["order_id"])
    op.create_index("ix_freelance_deliverables_created_at", "freelance_deliverables", ["created_at"])

    # ------------------------------ reviews ----------------------------- #
    op.create_table(
        "freelance_reviews",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("order_id", _uuid(), nullable=False),
        sa.Column("reviewer_id", _uuid(), nullable=False),
        sa.Column("reviewee_id", _uuid(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["order_id"], ["freelance_orders.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewer_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewee_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("order_id", "reviewer_id", name="uq_review_order_reviewer"),
    )
    op.create_index("ix_freelance_reviews_reviewee", "freelance_reviews", ["reviewee_id"])
    op.create_index("ix_freelance_reviews_created_at", "freelance_reviews", ["created_at"])

    # ----------------------------- favorites ---------------------------- #
    op.create_table(
        "freelance_favorites",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("user_id", _uuid(), nullable=False),
        sa.Column("target_type", sa.String(length=16), nullable=False),
        sa.Column("target_id", _uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", "target_type", "target_id", name="uq_favorite_user_target"),
    )
    op.create_index("ix_freelance_favorites_user", "freelance_favorites", ["user_id"])

    # ------------------------- freelance chat --------------------------- #
    op.create_table(
        "freelance_conversations",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("context_type", sa.String(length=16), nullable=False),
        sa.Column("context_id", _uuid(), nullable=False),
        sa.Column("client_id", _uuid(), nullable=False),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=True),
        sa.Column("client_last_read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("freelancer_last_read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_message_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freelancer_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("context_type", "context_id", name="uq_freelance_conv_context"),
    )
    op.create_index("ix_freelance_conversations_client", "freelance_conversations", ["client_id"])
    op.create_index("ix_freelance_conversations_freelancer", "freelance_conversations", ["freelancer_id"])
    op.create_index("ix_freelance_conversations_last_message_at", "freelance_conversations", ["last_message_at"])

    op.create_table(
        "freelance_messages",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("conversation_id", _uuid(), nullable=False),
        sa.Column("sender_id", _uuid(), nullable=False),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("message_type", sa.String(length=16), nullable=False, server_default="text"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("edited_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["conversation_id"], ["freelance_conversations.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_messages_created_at", "freelance_messages", ["created_at"])
    op.create_index("ix_freelance_messages_conv_created", "freelance_messages", ["conversation_id", "created_at"])

    op.create_table(
        "freelance_message_attachments",
        sa.Column("id", _uuid(), primary_key=True, nullable=False),
        sa.Column("message_id", _uuid(), nullable=False),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("file_name", sa.String(length=255), nullable=False),
        sa.Column("mime_type", sa.String(length=128), nullable=False),
        sa.Column("file_size", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("attachment_type", sa.String(length=16), nullable=False, server_default="other"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["message_id"], ["freelance_messages.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_msg_attachments_message", "freelance_message_attachments", ["message_id"])


def downgrade() -> None:
    op.drop_table("freelance_message_attachments")
    op.drop_table("freelance_messages")
    op.drop_table("freelance_conversations")
    op.drop_table("freelance_favorites")
    op.drop_table("freelance_reviews")
    op.drop_table("freelance_deliverables")
    op.drop_table("freelance_milestones")
    op.drop_table("freelance_orders")
    op.drop_table("freelance_proposals")
    op.drop_table("freelance_projects")
    op.drop_table("freelancer_profiles")
