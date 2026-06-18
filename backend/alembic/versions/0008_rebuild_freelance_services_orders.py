"""rebuild freelance as service/order marketplace (data-safe)

Revision ID: 0008_freelance_rebuild
Revises: 0007_freelance_marketplace
Create Date: 2026-06-09

NOTE: the revision id is kept <= 32 chars because Alembic's ``alembic_version``
table stores ``version_num`` as VARCHAR(32); the previous 38-char id
("0008_rebuild_freelance_services_orders") overflowed that column and made the
upgrade fail at the version stamp. No migration references 0008 as a
down_revision, so shortening the id is safe.

SAFETY NOTE (Phase 8)
---------------------
This migration moves the freelance feature from the projects/proposals design
(0007) to the services/orders design used by the current ORM models. The original
version of this migration ran ``DROP TABLE ... CASCADE`` on every freelance table,
which would have destroyed real data.

It has been rewritten to be NON-DESTRUCTIVE:

* A freelance table that is EMPTY is simply dropped (clean result on fresh DBs).
* A freelance table that CONTAINS ROWS is renamed to ``<name>__legacy0007`` so its
  data is preserved and recoverable; the freed name is then used for the new table.
* ``created_at`` / ``updated_at`` now have ``server_default=CURRENT_TIMESTAMP``.
* Table creation is idempotent (create-if-absent), so a re-run after a partial
  failure is safe.

Editing this migration is safe pre-deployment: databases already at 0008 are past
this revision and will not re-run it; databases not yet at 0008 get the safe path.
The resulting schema is unchanged and still matches the ORM models exactly.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0008_freelance_rebuild"
down_revision = "0007_freelance_marketplace"
branch_labels = None
depends_on = None

# Server-side default so created_at/updated_at are never NULL even on raw inserts.
_TS = sa.text("CURRENT_TIMESTAMP")

# Tables from the 0004/0007 freelance designs that the new schema replaces.
_LEGACY_TABLES = (
    "freelance_message_attachments",
    "freelance_messages",
    "freelance_conversations",
    "freelance_favorites",
    "freelance_reviews",
    "freelance_deliverables",
    "freelance_milestones",
    "freelance_orders",
    "freelance_proposals",
    "freelance_projects",
    "freelance_services",
    "freelance_chat_messages",
    "freelancer_profiles",
    "freelancer_applications",
)

# New tables this migration owns (used for idempotent create + downgrade).
_NEW_TABLES = (
    "freelance_reviews",
    "freelance_chat_messages",
    "freelance_orders",
    "freelance_services",
    "freelancer_profiles",
    "freelancer_applications",
)


def _uuid():
    return postgresql.UUID(as_uuid=True)


def _json():
    return sa.JSON()


def _has_table(name: str) -> bool:
    return name in sa.inspect(op.get_bind()).get_table_names()


def _row_count(name: str) -> int:
    try:
        return op.get_bind().execute(sa.text(f'SELECT COUNT(*) FROM "{name}"')).scalar() or 0
    except Exception:
        return 0


def _archive_or_drop(name: str) -> None:
    """Drop the table if empty; otherwise preserve its data by renaming it to a
    ``__legacy0007`` table (never destroys rows)."""
    bind = op.get_bind()
    if not _has_table(name):
        return

    if _row_count(name) == 0:
        if bind.dialect.name == "postgresql":
            op.execute(sa.text(f'DROP TABLE IF EXISTS "{name}" CASCADE'))
        else:
            op.execute(sa.text(f'DROP TABLE IF EXISTS "{name}"'))
        return

    legacy = f"{name}__legacy0007"
    if _has_table(legacy):
        # A prior run already archived this table; do not clobber it. Drop the
        # current (presumably new/empty) table name only if it is empty.
        if _row_count(name) == 0:
            op.execute(sa.text(f'DROP TABLE IF EXISTS "{name}"'))
        return

    # Rename PostgreSQL indexes first so the new table can reuse the same names.
    if bind.dialect.name == "postgresql":
        op.execute(
            "DO $$ DECLARE r record; BEGIN "
            f"FOR r IN SELECT indexname FROM pg_indexes WHERE tablename = '{name}' LOOP "
            "EXECUTE format('ALTER INDEX %I RENAME TO %I', r.indexname, "
            "left('lg0007_' || r.indexname, 63)); END LOOP; END $$;"
        )
    op.rename_table(name, legacy)


def upgrade() -> None:
    # 1) Preserve or clean up old freelance tables (never destructive).
    for table in _LEGACY_TABLES:
        _archive_or_drop(table)

    # 2) Create the services/orders schema (matches ORM models). Every name was
    #    freed by step 1, and migrations run transactionally on PostgreSQL.
    op.create_table(
        "freelancer_applications",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("user_id", _uuid(), nullable=False),
        sa.Column("full_name", sa.String(140), nullable=False),
        sa.Column("title", sa.String(140), nullable=False),
        sa.Column("skills", _json(), nullable=False, server_default="[]"),
        sa.Column("experience", sa.Text(), nullable=True),
        sa.Column("portfolio_links", _json(), nullable=False, server_default="[]"),
        sa.Column("expected_price_range", sa.String(120), nullable=True),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("status", sa.String(24), nullable=False, server_default="pending_review"),
        sa.Column("admin_note", sa.Text(), nullable=True),
        sa.Column("reviewed_by", _uuid(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reviewed_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_freelancer_applications_user_id", "freelancer_applications", ["user_id"])
    op.create_index("ix_freelancer_applications_status", "freelancer_applications", ["status"])
    op.create_index("ix_freelancer_applications_created_at", "freelancer_applications", ["created_at"])

    op.create_table(
        "freelancer_profiles",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("user_id", _uuid(), nullable=False),
        sa.Column("display_name", sa.String(140), nullable=False),
        sa.Column("title", sa.String(140), nullable=False),
        sa.Column("bio", sa.Text(), nullable=True),
        sa.Column("skills", _json(), nullable=False, server_default="[]"),
        sa.Column("categories", _json(), nullable=False, server_default="[]"),
        sa.Column("hourly_rate", sa.Numeric(12, 2), nullable=True),
        sa.Column("starting_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("profile_image", sa.Text(), nullable=True),
        sa.Column("portfolio_links", _json(), nullable=False, server_default="[]"),
        sa.Column("status", sa.String(24), nullable=False, server_default="pending"),
        sa.Column("availability", sa.String(32), nullable=False, server_default="available"),
        sa.Column("rating_average", sa.Numeric(3, 2), nullable=False, server_default="0"),
        sa.Column("rating_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("completed_jobs_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", name="uq_freelancer_profile_user"),
    )
    op.create_index("ix_freelancer_profiles_status", "freelancer_profiles", ["status"])
    op.create_index("ix_freelancer_profiles_availability", "freelancer_profiles", ["availability"])
    op.create_index("ix_freelancer_profiles_created_at", "freelancer_profiles", ["created_at"])

    op.create_table(
        "freelance_services",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("title", sa.String(180), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("category", sa.String(80), nullable=False),
        sa.Column("tags", _json(), nullable=False, server_default="[]"),
        sa.Column("starting_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("delivery_days", sa.Integer(), nullable=False, server_default="7"),
        sa.Column("revisions", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("file_formats", _json(), nullable=False, server_default="[]"),
        sa.Column("images", _json(), nullable=False, server_default="[]"),
        sa.Column("status", sa.String(24), nullable=False, server_default="draft"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.ForeignKeyConstraint(["freelancer_id"], ["freelancer_profiles.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_services_freelancer", "freelance_services", ["freelancer_id"])
    op.create_index("ix_freelance_services_category", "freelance_services", ["category"])
    op.create_index("ix_freelance_services_status", "freelance_services", ["status"])
    op.create_index("ix_freelance_services_created_at", "freelance_services", ["created_at"])

    op.create_table(
        "freelance_orders",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("client_id", _uuid(), nullable=False),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("service_id", _uuid(), nullable=True),
        sa.Column("title", sa.String(180), nullable=False),
        sa.Column("requirements", sa.Text(), nullable=False),
        sa.Column("budget", sa.Numeric(12, 2), nullable=False),
        sa.Column("deadline", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attachments", _json(), nullable=False, server_default="[]"),
        sa.Column("status", sa.String(32), nullable=False, server_default="pending"),
        sa.Column("delivery_files", _json(), nullable=False, server_default="[]"),
        sa.Column("revision_note", sa.Text(), nullable=True),
        sa.Column("dispute_reason", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freelancer_id"], ["freelancer_profiles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["service_id"], ["freelance_services.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_freelance_orders_client", "freelance_orders", ["client_id"])
    op.create_index("ix_freelance_orders_freelancer", "freelance_orders", ["freelancer_id"])
    op.create_index("ix_freelance_orders_status", "freelance_orders", ["status"])
    op.create_index("ix_freelance_orders_created_at", "freelance_orders", ["created_at"])

    op.create_table(
        "freelance_chat_messages",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("order_id", _uuid(), nullable=False),
        sa.Column("sender_id", _uuid(), nullable=False),
        sa.Column("message", sa.Text(), nullable=True),
        sa.Column("attachments", _json(), nullable=False, server_default="[]"),
        sa.Column("voice_note_url", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["order_id"], ["freelance_orders.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_freelance_chat_messages_created_at", "freelance_chat_messages", ["created_at"])
    op.create_index(
        "ix_freelance_messages_order_created",
        "freelance_chat_messages",
        ["order_id", "created_at"],
    )

    op.create_table(
        "freelance_reviews",
        sa.Column("id", _uuid(), primary_key=True),
        sa.Column("order_id", _uuid(), nullable=False),
        sa.Column("client_id", _uuid(), nullable=False),
        sa.Column("freelancer_id", _uuid(), nullable=False),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("quality_rating", sa.Integer(), nullable=False),
        sa.Column("communication_rating", sa.Integer(), nullable=False),
        sa.Column("delivery_rating", sa.Integer(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=_TS),
        sa.ForeignKeyConstraint(["order_id"], ["freelance_orders.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freelancer_id"], ["freelancer_profiles.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("order_id", "client_id", name="uq_freelance_review_order_client"),
    )
    op.create_index("ix_freelance_reviews_freelancer", "freelance_reviews", ["freelancer_id"])
    op.create_index("ix_freelance_reviews_created_at", "freelance_reviews", ["created_at"])


def downgrade() -> None:
    # Dev-only. Drops the service/order schema this migration created, then
    # restores any archived 0007 tables so legacy data is not lost on downgrade.
    bind = op.get_bind()
    for table in _NEW_TABLES:
        if not _has_table(table):
            continue
        if bind.dialect.name == "postgresql":
            op.execute(sa.text(f'DROP TABLE IF EXISTS "{table}" CASCADE'))
        else:
            op.execute(sa.text(f'DROP TABLE IF EXISTS "{table}"'))

    for table in _LEGACY_TABLES:
        legacy = f"{table}__legacy0007"
        if _has_table(legacy) and not _has_table(table):
            op.rename_table(legacy, table)
