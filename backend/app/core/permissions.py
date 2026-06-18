from __future__ import annotations

"""Role / permission constants for the R2V platform.

The platform uses a single ``role`` column on the user. Permissions are derived
from the role via :func:`permissions_for_role`. This keeps role storage simple
while still giving the API and UI a fine-grained capability list to gate on.

Roles (in increasing privilege):
    user        - default account
    freelancer  - approved freelancer (can offer services)
    admin       - platform moderation / management
    super_admin - owner-level, can manage admins and system settings
"""

ROLE_USER = "user"
ROLE_FREELANCER = "freelancer"
ROLE_ADMIN = "admin"
ROLE_SUPER_ADMIN = "super_admin"

ALL_ROLES = (ROLE_USER, ROLE_FREELANCER, ROLE_ADMIN, ROLE_SUPER_ADMIN)

# Roles that may open the admin dashboard / use admin endpoints.
ADMIN_ROLES = (ROLE_ADMIN, ROLE_SUPER_ADMIN)

# Permissions granted to any admin (and, by inheritance, super_admin).
ADMIN_PERMISSIONS: tuple[str, ...] = (
    "view_admin_dashboard",
    "view_all_users",
    "edit_users",
    "ban_users",
    "unban_users",
    "view_all_generations",
    "manage_failed_generations",
    "delete_bad_generations",
    "view_all_3d_models",
    "moderate_models",
    "remove_inappropriate_models",
    "view_orders",
    "manage_orders",
    "assign_freelancers",
    "view_freelancers",
    "approve_freelancers",
    "reject_freelancers",
    "view_reports",
    "resolve_reports",
    "view_payments",
    "view_revenue",
    "view_logs",
    "view_analytics",
    "manage_categories",
    "manage_platform_content",
)

# Permissions reserved for super_admin only.
SUPER_ADMIN_PERMISSIONS: tuple[str, ...] = (
    "delete_users_permanently",
    "change_user_roles",
    "view_admins",
    "create_admins",
    "promote_users_to_admin",
    "demote_admins",
    "manage_admins",
    "manage_api_keys",
    "manage_ai_provider_keys",
    "manage_payment_settings",
    "delete_database_data",
    "change_system_settings",
)

# Full set super_admin holds (admin perms + super-only perms).
ALL_PERMISSIONS: tuple[str, ...] = ADMIN_PERMISSIONS + SUPER_ADMIN_PERMISSIONS


def permissions_for_role(role: str | None) -> list[str]:
    """Return the list of permission strings a role is granted."""
    if role == ROLE_SUPER_ADMIN:
        return list(ALL_PERMISSIONS)
    if role == ROLE_ADMIN:
        return list(ADMIN_PERMISSIONS)
    return []


def role_has_permission(role: str | None, permission: str) -> bool:
    return permission in permissions_for_role(role)


def is_admin_role(role: str | None) -> bool:
    return role in ADMIN_ROLES
