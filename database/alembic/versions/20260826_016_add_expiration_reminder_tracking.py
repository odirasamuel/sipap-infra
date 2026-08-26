"""Add expiration reminder tracking column to users table

Revision ID: 20260826_016
Revises: 20260825_015
Create Date: 2026-08-26

Adds tracking for 24-hour pre-expiration reminders sent to users.
This is separate from renewal_reminder_sent_at (for grace period reminders).

Schema Changes:
    - users: Add expiration_reminder_sent_at column
    - Index for efficient reminder queries
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260826_016'
down_revision = '20260825_015'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Add expiration reminder tracking"""

    # ===========================================================================
    # 1. Add expiration_reminder_sent_at column to users table
    # ===========================================================================

    # expiration_reminder_sent_at: Track when we sent 24-hour pre-expiration reminder
    # Different from renewal_reminder_sent_at which is for grace period reminders
    op.add_column(
        'users',
        sa.Column('expiration_reminder_sent_at', sa.TIMESTAMP(), nullable=True)
    )

    # ===========================================================================
    # 2. Create index for efficient reminder queries
    # ===========================================================================

    # Index for finding users who need expiration reminders
    # Query: WHERE subscription_status = 'active'
    #        AND subscription_expires_at BETWEEN NOW() AND NOW() + '24 hours'
    #        AND (expiration_reminder_sent_at IS NULL OR ...)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_expiration_reminder
        ON users(subscription_expires_at, expiration_reminder_sent_at)
        WHERE subscription_status = 'active'
    """)


def downgrade() -> None:
    """Revert migration: Remove expiration reminder tracking"""

    # Drop index
    op.execute("DROP INDEX IF EXISTS idx_users_expiration_reminder")

    # Drop column
    op.drop_column('users', 'expiration_reminder_sent_at')
