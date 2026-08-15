"""Clear corrupted league external_ids

This migration clears all external_ids from the leagues table to fix
the corruption caused by name collision bugs in _get_or_create_league.

The issue: Multiple leagues with the same name (e.g., "Premier League" exists
in England=39, Belarus=117, Wales=113) were incorrectly sharing external_ids
because the lookup fell back to name matching instead of using external_id
as the primary key.

Result: "Bolivia tomorrow" query returned Russian matches because a Russian
league got assigned Bolivia's external_id (651).

Fix: Clear all external_ids and re-run fixture_manager with the updated
_get_or_create_league that uses external_id as the PRIMARY lookup key.

Revision ID: 20260815_012
Revises: 20260806_011
Create Date: 2026-08-15
"""
from alembic import op

# revision identifiers, used by Alembic
revision = '20260815_012'
down_revision = '20260806_011'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Clear all external_ids from leagues table to fix corruption."""
    # Clear all external_ids - fixture_manager will repopulate correctly
    op.execute("UPDATE leagues SET external_id = NULL, country = NULL")

    # Log the change
    print("Cleared all league external_ids and countries")
    print("Run fixture_manager to repopulate with correct API-Football IDs")


def downgrade() -> None:
    """Cannot restore external_ids automatically - requires re-running fixture_manager."""
    # This is a one-way migration - the corrupted data cannot be restored
    # and wouldn't be desirable anyway
    print("WARNING: Cannot restore corrupted external_ids")
    print("Re-run fixture_manager to repopulate")
