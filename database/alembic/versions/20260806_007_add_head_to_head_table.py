"""Add head_to_head table for historical matchups

Revision ID: 20260806_007
Revises: 20260806_006
Create Date: 2026-08-06

Creates the head_to_head table to store historical head-to-head records between teams
from API-Football. Useful for statistical analysis and prediction models.

Schema Design:
- team_1_id, team_2_id: API-Football team IDs (team_1_id < team_2_id for consistency)
- last_10_matches: JSONB array of last 10 H2H match results
- team_1_wins, draws, team_2_wins: Overall H2H record counts

Unique constraint: (team_1_id, team_2_id) with CHECK (team_1_id < team_2_id)
This ensures one row per pair regardless of order (Arsenal vs Chelsea = Chelsea vs Arsenal)

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_007'
down_revision = '20260806_006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create head_to_head table"""

    # Create head_to_head table
    op.execute("""
        CREATE TABLE head_to_head (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            team_1_id INT NOT NULL,
            team_2_id INT NOT NULL,
            last_10_matches JSONB NOT NULL,
            team_1_wins INT NOT NULL,
            draws INT NOT NULL,
            team_2_wins INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            UNIQUE(team_1_id, team_2_id),
            CHECK (team_1_id < team_2_id)
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_head_to_head_team_1
        ON head_to_head(team_1_id)
    """)

    op.execute("""
        CREATE INDEX idx_head_to_head_team_2
        ON head_to_head(team_2_id)
    """)

    op.execute("""
        CREATE INDEX idx_head_to_head_updated
        ON head_to_head(updated_at DESC)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE head_to_head IS
        'Head-to-head records between teams from API-Football (last 10 matches)'
    """)

    op.execute("""
        COMMENT ON COLUMN head_to_head.team_1_id IS
        'API-Football team ID (lower ID, ensures consistent ordering)'
    """)

    op.execute("""
        COMMENT ON COLUMN head_to_head.team_2_id IS
        'API-Football team ID (higher ID, ensures consistent ordering)'
    """)

    op.execute("""
        COMMENT ON COLUMN head_to_head.last_10_matches IS
        'JSONB array of last 10 H2H match results with scores and dates'
    """)


def downgrade() -> None:
    """Revert migration: Drop head_to_head table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_head_to_head_updated')
    op.execute('DROP INDEX IF EXISTS idx_head_to_head_team_2')
    op.execute('DROP INDEX IF EXISTS idx_head_to_head_team_1')

    # Drop table
    op.execute('DROP TABLE IF EXISTS head_to_head CASCADE')
