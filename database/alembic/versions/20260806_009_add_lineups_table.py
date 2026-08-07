"""Add lineups table for match starting lineups

Revision ID: 20260806_009
Revises: 20260806_008
Create Date: 2026-08-06

Creates the lineups table to store starting lineups and formations from API-Football.
Helps statistical agents assess team tactics and player selection.

Schema Design:
- fixture_id: API-Football fixture ID (one row per fixture)
- home_team_id, away_team_id: API-Football team IDs
- home_formation, away_formation: Formation strings (4-3-3, 4-4-2, etc.)
- home_lineup, away_lineup: JSONB arrays of starting XI player objects
- home_substitutes, away_substitutes: JSONB arrays of substitute players
- home_coach, away_coach: Coach names

Unique constraint: fixture_id (one lineup record per fixture)

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_009'
down_revision = '20260806_008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create lineups table"""

    # Create lineups table
    op.execute("""
        CREATE TABLE lineups (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            fixture_id INT NOT NULL UNIQUE,
            home_team_id INT NOT NULL,
            away_team_id INT NOT NULL,
            home_formation VARCHAR(10),
            away_formation VARCHAR(10),
            home_lineup JSONB NOT NULL,
            away_lineup JSONB NOT NULL,
            home_substitutes JSONB,
            away_substitutes JSONB,
            home_coach VARCHAR(255),
            away_coach VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_lineups_fixture
        ON lineups(fixture_id)
    """)

    op.execute("""
        CREATE INDEX idx_lineups_home_team
        ON lineups(home_team_id)
    """)

    op.execute("""
        CREATE INDEX idx_lineups_away_team
        ON lineups(away_team_id)
    """)

    op.execute("""
        CREATE INDEX idx_lineups_formation
        ON lineups(home_formation, away_formation)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE lineups IS
        'Match starting lineups from API-Football (formations, players, coaches)'
    """)

    op.execute("""
        COMMENT ON COLUMN lineups.fixture_id IS
        'API-Football fixture ID (unique per match)'
    """)

    op.execute("""
        COMMENT ON COLUMN lineups.home_formation IS
        'Home team formation (4-3-3, 4-4-2, 3-5-2, etc.)'
    """)

    op.execute("""
        COMMENT ON COLUMN lineups.home_lineup IS
        'JSONB array of starting XI player objects with positions'
    """)

    op.execute("""
        COMMENT ON COLUMN lineups.home_substitutes IS
        'JSONB array of substitute players on bench'
    """)


def downgrade() -> None:
    """Revert migration: Drop lineups table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_lineups_formation')
    op.execute('DROP INDEX IF EXISTS idx_lineups_away_team')
    op.execute('DROP INDEX IF EXISTS idx_lineups_home_team')
    op.execute('DROP INDEX IF EXISTS idx_lineups_fixture')

    # Drop table
    op.execute('DROP TABLE IF EXISTS lineups CASCADE')
