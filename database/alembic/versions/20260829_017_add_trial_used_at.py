"""Add trial_used_at column for trial usage tracking

Revision ID: 20260829_017
Revises: 20260826_016
Create Date: 2026-08-29

This migration adds the trial_used_at column to track when a user's
one free trial prediction was used.

Business Logic:
    - Trial users get ONE free prediction request only (not unlimited)
    - trial_used_at = NULL means trial not used yet
    - trial_used_at = timestamp means trial was used at that time
    - After trial is used, users must subscribe to continue

Schema Changes:
    - users: Add trial_used_at (TIMESTAMP, nullable)
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260829_017'
down_revision = '20260826_016'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Add trial_used_at column to users table"""

    # Add trial_used_at column to users table
    # NULL = trial not used yet
    # Timestamp = when trial was used
    op.add_column(
        'users',
        sa.Column('trial_used_at', sa.TIMESTAMP(), nullable=True)
    )

    # Create index for efficient trial status queries
    op.create_index(
        'idx_users_trial_used_at',
        'users',
        ['trial_used_at']
    )


def downgrade() -> None:
    """Revert migration: Remove trial_used_at column"""

    # Drop index
    op.drop_index('idx_users_trial_used_at', table_name='users')

    # Drop column
    op.drop_column('users', 'trial_used_at')
