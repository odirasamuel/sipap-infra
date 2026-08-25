"""Simplify subscription tiers for MVP launch

Revision ID: 20260825_015
Revises: 20260824_014
Create Date: 2026-08-25

MVP Simplification:
- Single tier ($2/week) with unlimited everything
- No message limit tracking needed
- Pro tier deactivated (kept for future use)

Changes:
    - subscription_plans.basic: message_limit = NULL, features = all Pro features
    - subscription_plans.pro: is_active = false
"""
from alembic import op


# revision identifiers, used by Alembic.
revision = '20260825_015'
down_revision = '20260824_014'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Simplify to single unlimited tier."""

    # Update Basic tier: unlimited messages, all features
    op.execute("""
        UPDATE subscription_plans
        SET
            message_limit = NULL,
            features = '["Unlimited predictions", "All sports coverage", "Deep analysis", "Priority support"]'::jsonb
        WHERE tier = 'basic'
    """)

    # Deactivate Pro tier (keep for future use)
    op.execute("""
        UPDATE subscription_plans
        SET is_active = false
        WHERE tier = 'pro'
    """)


def downgrade() -> None:
    """Restore original tier configuration."""

    # Restore Basic tier original values
    op.execute("""
        UPDATE subscription_plans
        SET
            message_limit = 35,
            features = '["5 predictions per day", "Soccer coverage", "Basic analysis"]'::jsonb
        WHERE tier = 'basic'
    """)

    # Reactivate Pro tier
    op.execute("""
        UPDATE subscription_plans
        SET is_active = true
        WHERE tier = 'pro'
    """)
