"""Add subscription auth fields for user journey

Revision ID: 20260823_013
Revises: 20260815_012
Create Date: 2026-08-23

This migration adds fields and tables required for the user authentication,
registration, and subscription system:

Schema Changes:
    - users: Add email, name, country, paystack_customer_id, is_active, deleted_at
    - subscription_events: Add paystack_reference, provider columns

New Tables:
    - subscription_plans: Tier definitions (basic, pro) with pricing
    - user_registration_tokens: Temporary tokens for signup links

Seed Data:
    - Basic tier: $2/week, 35 messages/week
    - Pro tier: $5/week, unlimited messages
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision = '20260823_013'
down_revision = '20260815_012'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Add subscription auth fields and tables"""

    # ===========================================================================
    # 1. Add new columns to users table
    # ===========================================================================
    op.add_column('users', sa.Column('email', sa.String(255), nullable=True))
    op.add_column('users', sa.Column('name', sa.String(200), nullable=True))
    op.add_column('users', sa.Column('country', sa.String(2), nullable=True))  # ISO 3166-1 alpha-2
    op.add_column('users', sa.Column('paystack_customer_id', sa.String(100), nullable=True))
    op.add_column('users', sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('users', sa.Column('deleted_at', sa.TIMESTAMP(), nullable=True))

    # Create indexes on new columns
    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_country', 'users', ['country'])
    op.create_index('idx_users_is_active', 'users', ['is_active'])
    op.create_index('idx_users_deleted_at', 'users', ['deleted_at'])
    op.create_index('idx_users_paystack_customer_id', 'users', ['paystack_customer_id'])

    # Composite index for subscription lookups
    op.create_index(
        'idx_users_active_subscription',
        'users',
        ['phone_number', 'is_active', 'subscription_status', 'subscription_expires_at']
    )

    # ===========================================================================
    # 2. Add columns to subscription_events table
    # ===========================================================================
    op.add_column('subscription_events', sa.Column('paystack_reference', sa.String(100), nullable=True))
    op.add_column('subscription_events', sa.Column('provider', sa.String(20), nullable=True))  # 'stripe' or 'paystack'

    op.create_index('idx_subscription_events_paystack_reference', 'subscription_events', ['paystack_reference'])
    op.create_index('idx_subscription_events_provider', 'subscription_events', ['provider'])

    # ===========================================================================
    # 3. Create subscription_plans table
    # ===========================================================================
    op.create_table(
        'subscription_plans',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('name', sa.String(50), nullable=False),
        sa.Column('tier', sa.String(20), nullable=False),  # 'basic', 'pro'
        sa.Column('price_usd_cents', sa.Integer(), nullable=False),  # 200 = $2, 500 = $5
        sa.Column('duration_days', sa.Integer(), server_default='7', nullable=False),
        sa.Column('message_limit', sa.Integer(), nullable=True),  # NULL = unlimited
        sa.Column('features', JSONB(), server_default=sa.text("'[]'::jsonb"), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('created_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'), nullable=False),
        sa.Column('updated_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'), nullable=False),
    )

    op.create_index('idx_subscription_plans_tier', 'subscription_plans', ['tier'])
    op.create_index('idx_subscription_plans_is_active', 'subscription_plans', ['is_active'])

    # Seed subscription plans
    op.execute("""
        INSERT INTO subscription_plans (name, tier, price_usd_cents, duration_days, message_limit, features)
        VALUES
            ('Basic Weekly', 'basic', 200, 7, 35, '["5 predictions per day", "Soccer coverage", "Basic analysis"]'::jsonb),
            ('Pro Weekly', 'pro', 500, 7, NULL, '["Unlimited predictions", "All sports coverage", "Deep analysis", "Priority support"]'::jsonb)
    """)

    # ===========================================================================
    # 4. Create user_registration_tokens table
    # ===========================================================================
    op.create_table(
        'user_registration_tokens',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('phone_number', sa.String(20), nullable=False),
        sa.Column('token', sa.String(64), nullable=False, unique=True),  # SHA256 hash
        sa.Column('expires_at', sa.TIMESTAMP(), nullable=False),
        sa.Column('used_at', sa.TIMESTAMP(), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'), nullable=False),
    )

    op.create_index('idx_registration_tokens_token', 'user_registration_tokens', ['token'])
    op.create_index('idx_registration_tokens_phone', 'user_registration_tokens', ['phone_number'])
    op.create_index('idx_registration_tokens_expires_at', 'user_registration_tokens', ['expires_at'])


def downgrade() -> None:
    """Revert migration: Remove subscription auth fields and tables"""

    # Drop new tables
    op.drop_table('user_registration_tokens')
    op.drop_table('subscription_plans')

    # Drop indexes from subscription_events
    op.drop_index('idx_subscription_events_provider', table_name='subscription_events')
    op.drop_index('idx_subscription_events_paystack_reference', table_name='subscription_events')

    # Drop columns from subscription_events
    op.drop_column('subscription_events', 'provider')
    op.drop_column('subscription_events', 'paystack_reference')

    # Drop indexes from users
    op.drop_index('idx_users_active_subscription', table_name='users')
    op.drop_index('idx_users_paystack_customer_id', table_name='users')
    op.drop_index('idx_users_deleted_at', table_name='users')
    op.drop_index('idx_users_is_active', table_name='users')
    op.drop_index('idx_users_country', table_name='users')
    op.drop_index('idx_users_email', table_name='users')

    # Drop columns from users
    op.drop_column('users', 'deleted_at')
    op.drop_column('users', 'is_active')
    op.drop_column('users', 'paystack_customer_id')
    op.drop_column('users', 'country')
    op.drop_column('users', 'name')
    op.drop_column('users', 'email')
