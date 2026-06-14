"""Initial database schema and seed data

Revision ID: 20260614_001
Revises: None
Create Date: 2026-06-14

This baseline migration creates the initial SIPAP database schema with 10 tables
and loads reference data (4 sports, 5 leagues).

Tables Created:
    - users: User accounts and subscription management
    - sports: Supported sports (soccer, basketball, etc.)
    - leagues: Sports leagues and competitions
    - teams: Sports teams
    - matches: Match schedules and results
    - predictions: AI-generated predictions
    - prediction_evidence: Supporting evidence for predictions
    - agent_contributions: Agent participation tracking
    - subscription_events: Subscription lifecycle events
    - user_feedback: User feedback on predictions

Seed Data:
    - 4 sports: soccer, basketball, american_football, tennis
    - 5 leagues: Premier League, NBA, NFL, La Liga, Bundesliga
"""
from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision = '20260614_001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create initial schema and load seed data"""

    # Read and execute schema.sql
    schema_sql_path = os.path.join(os.path.dirname(__file__), '../../schema.sql')
    with open(schema_sql_path, 'r') as f:
        schema_sql = f.read()

    # Execute schema SQL (creates all tables and indexes)
    op.execute(schema_sql)

    # Read and execute seed_data.sql
    seed_sql_path = os.path.join(os.path.dirname(__file__), '../../seed_data.sql')
    with open(seed_sql_path, 'r') as f:
        seed_sql = f.read()

    # Execute seed data SQL (inserts reference data)
    op.execute(seed_sql)


def downgrade() -> None:
    """Revert migration: Drop all tables"""

    # Drop tables in reverse dependency order
    op.execute('DROP TABLE IF EXISTS user_feedback CASCADE')
    op.execute('DROP TABLE IF EXISTS subscription_events CASCADE')
    op.execute('DROP TABLE IF EXISTS agent_contributions CASCADE')
    op.execute('DROP TABLE IF EXISTS prediction_evidence CASCADE')
    op.execute('DROP TABLE IF EXISTS predictions CASCADE')
    op.execute('DROP TABLE IF EXISTS matches CASCADE')
    op.execute('DROP TABLE IF EXISTS teams CASCADE')
    op.execute('DROP TABLE IF EXISTS leagues CASCADE')
    op.execute('DROP TABLE IF EXISTS sports CASCADE')
    op.execute('DROP TABLE IF EXISTS users CASCADE')
