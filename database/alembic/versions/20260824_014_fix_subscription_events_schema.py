"""Fix subscription_events schema and add payment infrastructure

Revision ID: 20260824_014
Revises: 20260815_012
Create Date: 2026-08-24

CRITICAL FIX: The payment webhook handler tries to INSERT columns that don't exist:
- amount_usd: Payment amount for tracking
- stripe_session_id: Checkout session ID (different from stripe_event_id!)
- flutterwave_reference: Flutterwave tx_ref
- metadata: JSONB for payment details

This migration also adds:
- Idempotency constraints via unique partial indexes
- Grace period support for expired subscriptions
- payment_attempts table for comprehensive tracking
- Risk mitigation indexes

Schema Changes:
    - subscription_events: Add amount_usd, stripe_session_id, flutterwave_reference,
                          metadata, status, failure_reason columns
    - users: Add subscription_grace_until, renewal_reminder_sent_at columns

New Tables:
    - payment_attempts: Track every payment attempt for reconciliation
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

# revision identifiers, used by Alembic.
revision = '20260824_014'
down_revision = '20260815_012'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Fix subscription_events schema and add payment infrastructure"""

    # ===========================================================================
    # 1. Fix subscription_events table - Add missing columns
    # ===========================================================================

    # Add amount_usd column (payment amount for tracking)
    op.add_column(
        'subscription_events',
        sa.Column('amount_usd', sa.DECIMAL(10, 2), nullable=True)
    )

    # Add stripe_session_id (checkout session ID - different from stripe_event_id)
    op.add_column(
        'subscription_events',
        sa.Column('stripe_session_id', sa.String(100), nullable=True)
    )

    # Add flutterwave_reference (tx_ref from Flutterwave)
    op.add_column(
        'subscription_events',
        sa.Column('flutterwave_reference', sa.String(100), nullable=True)
    )

    # Add metadata column (JSONB for payment details - different from event_data)
    op.add_column(
        'subscription_events',
        sa.Column('metadata', JSONB(), nullable=True)
    )

    # Add status column (for tracking payment state)
    op.add_column(
        'subscription_events',
        sa.Column('status', sa.String(20), server_default='succeeded', nullable=True)
    )

    # Add failure_reason column (for tracking why a payment failed)
    op.add_column(
        'subscription_events',
        sa.Column('failure_reason', sa.Text(), nullable=True)
    )

    # ===========================================================================
    # 2. Create idempotency indexes (unique partial indexes)
    # ===========================================================================

    # Unique index on stripe_session_id (only non-null values)
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_events_stripe_session_unique
        ON subscription_events(stripe_session_id)
        WHERE stripe_session_id IS NOT NULL
    """)

    # Unique index on paystack_reference (only non-null values)
    # Note: Regular index already exists from migration 013, this adds uniqueness
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_events_paystack_ref_unique
        ON subscription_events(paystack_reference)
        WHERE paystack_reference IS NOT NULL
    """)

    # Unique index on flutterwave_reference (only non-null values)
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_events_flutterwave_ref_unique
        ON subscription_events(flutterwave_reference)
        WHERE flutterwave_reference IS NOT NULL
    """)

    # Index for reconciliation queries (provider + status combination)
    op.create_index(
        'idx_sub_events_provider_status',
        'subscription_events',
        ['provider', 'status']
    )

    # ===========================================================================
    # 3. Add grace period columns to users table
    # ===========================================================================

    # subscription_grace_until: 24 hours after subscription_expires_at
    op.add_column(
        'users',
        sa.Column('subscription_grace_until', sa.TIMESTAMP(), nullable=True)
    )

    # renewal_reminder_sent_at: Track when we last sent a grace period reminder
    op.add_column(
        'users',
        sa.Column('renewal_reminder_sent_at', sa.TIMESTAMP(), nullable=True)
    )

    # Index for grace period queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_users_grace_until
        ON users(subscription_grace_until)
        WHERE subscription_grace_until IS NOT NULL
    """)

    # ===========================================================================
    # 4. Create payment_attempts table for comprehensive tracking
    # ===========================================================================

    op.create_table(
        'payment_attempts',
        sa.Column('id', UUID(), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('phone_number', sa.String(20), nullable=False),
        sa.Column('provider', sa.String(20), nullable=False),
        sa.Column('provider_reference', sa.String(100), nullable=True),
        sa.Column('amount_usd', sa.DECIMAL(10, 2), nullable=False),
        sa.Column('tier', sa.String(20), nullable=False),
        sa.Column('weeks', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(20), server_default='pending', nullable=False),
        sa.Column('failure_reason', sa.Text(), nullable=True),
        sa.Column('webhook_received_at', sa.TIMESTAMP(), nullable=True),
        sa.Column('processed_at', sa.TIMESTAMP(), nullable=True),
        sa.Column('retry_count', sa.Integer(), server_default='0', nullable=False),
        sa.Column('raw_webhook_payload', JSONB(), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'), nullable=False),
        sa.Column('updated_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'), nullable=False),
    )

    # Indexes for payment_attempts
    op.create_index('idx_payment_attempts_phone', 'payment_attempts', ['phone_number'])
    op.create_index('idx_payment_attempts_status', 'payment_attempts', ['status'])
    op.create_index('idx_payment_attempts_created', 'payment_attempts', ['created_at'])
    op.create_index('idx_payment_attempts_provider', 'payment_attempts', ['provider'])

    # Idempotency constraint for payment_attempts (provider + reference must be unique)
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_attempts_idempotency
        ON payment_attempts(provider, provider_reference)
        WHERE provider_reference IS NOT NULL
    """)


def downgrade() -> None:
    """Revert migration: Remove payment infrastructure"""

    # Drop payment_attempts table
    op.drop_table('payment_attempts')

    # Drop indexes from users
    op.execute("DROP INDEX IF EXISTS idx_users_grace_until")

    # Drop columns from users
    op.drop_column('users', 'renewal_reminder_sent_at')
    op.drop_column('users', 'subscription_grace_until')

    # Drop indexes from subscription_events
    op.drop_index('idx_sub_events_provider_status', table_name='subscription_events')
    op.execute("DROP INDEX IF EXISTS idx_sub_events_flutterwave_ref_unique")
    op.execute("DROP INDEX IF EXISTS idx_sub_events_paystack_ref_unique")
    op.execute("DROP INDEX IF EXISTS idx_sub_events_stripe_session_unique")

    # Drop columns from subscription_events
    op.drop_column('subscription_events', 'failure_reason')
    op.drop_column('subscription_events', 'status')
    op.drop_column('subscription_events', 'metadata')
    op.drop_column('subscription_events', 'flutterwave_reference')
    op.drop_column('subscription_events', 'stripe_session_id')
    op.drop_column('subscription_events', 'amount_usd')
