"""Add injuries table for player injury tracking

Revision ID: 20260806_008
Revises: 20260806_007
Create Date: 2026-08-06

Creates the injuries table to store player injury data from API-Football. Tracks
injuries for specific fixtures, helping statistical agents assess team strength.

Schema Design:
- fixture_id: API-Football fixture ID (the match affected by injury)
- team_id: API-Football team ID
- player_id: API-Football player ID
- player_name, player_position: Player details
- injury_type, injury_reason: Injury classification (e.g., "Knee Injury", "Suspended")
- expected_return_date: When player is expected to return

Unique constraint: (fixture_id, player_id) - one injury record per player per fixture

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_008'
down_revision = '20260806_007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create injuries table"""

    # Create injuries table
    op.execute("""
        CREATE TABLE injuries (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            fixture_id INT NOT NULL,
            team_id INT NOT NULL,
            player_id INT NOT NULL,
            player_name VARCHAR(255) NOT NULL,
            player_position VARCHAR(50),
            injury_type VARCHAR(255),
            injury_reason VARCHAR(255),
            expected_return_date DATE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            UNIQUE(fixture_id, player_id)
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_injuries_fixture
        ON injuries(fixture_id)
    """)

    op.execute("""
        CREATE INDEX idx_injuries_team
        ON injuries(team_id)
    """)

    op.execute("""
        CREATE INDEX idx_injuries_player
        ON injuries(player_id)
    """)

    op.execute("""
        CREATE INDEX idx_injuries_return_date
        ON injuries(expected_return_date)
        WHERE expected_return_date IS NOT NULL
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE injuries IS
        'Player injuries from API-Football (fixture-specific)'
    """)

    op.execute("""
        COMMENT ON COLUMN injuries.fixture_id IS
        'API-Football fixture ID (match affected by injury)'
    """)

    op.execute("""
        COMMENT ON COLUMN injuries.injury_reason IS
        'Injury reason: Knee Injury, Suspended, Red Card, etc.'
    """)

    op.execute("""
        COMMENT ON COLUMN injuries.expected_return_date IS
        'Date when player is expected to return (NULL if unknown)'
    """)


def downgrade() -> None:
    """Revert migration: Drop injuries table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_injuries_return_date')
    op.execute('DROP INDEX IF EXISTS idx_injuries_player')
    op.execute('DROP INDEX IF EXISTS idx_injuries_team')
    op.execute('DROP INDEX IF EXISTS idx_injuries_fixture')

    # Drop table
    op.execute('DROP TABLE IF EXISTS injuries CASCADE')
