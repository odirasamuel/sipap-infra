"""Add standings table for league standings

Revision ID: 20260806_005
Revises: 20260806_004
Create Date: 2026-08-06

Creates the standings table to store league standings from API-Football. Tracks team
positions, points, and form for league competitions.

Schema Design:
- league_id: API-Football league ID
- season: 4-digit season year (2024, 2025, etc.)
- team_id: API-Football team ID
- team_name: Team name from API
- rank: Current position in league table (1, 2, 3, ...)
- points: Total points
- matches_played, wins, draws, losses: Season statistics
- goals_for, goals_against, goal_difference: Goal statistics
- form: Recent form string (e.g., "WWDWL" = Win Win Draw Win Loss)
- description: Qualification info (e.g., "UEFA Champions League - Group Stage")

Unique constraint: (league_id, season, team_id) - one row per team per league-season

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_005'
down_revision = '20260806_004'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create standings table"""

    # Create standings table
    op.execute("""
        CREATE TABLE standings (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            league_id INT NOT NULL,
            season VARCHAR(4) NOT NULL,
            team_id INT NOT NULL,
            team_name VARCHAR(255) NOT NULL,
            rank INT NOT NULL,
            points INT NOT NULL,
            matches_played INT NOT NULL,
            wins INT NOT NULL,
            draws INT NOT NULL,
            losses INT NOT NULL,
            goals_for INT NOT NULL,
            goals_against INT NOT NULL,
            goal_difference INT NOT NULL,
            form VARCHAR(10),
            description VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            UNIQUE(league_id, season, team_id)
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_standings_league_season
        ON standings(league_id, season)
    """)

    op.execute("""
        CREATE INDEX idx_standings_team
        ON standings(team_id)
    """)

    op.execute("""
        CREATE INDEX idx_standings_rank
        ON standings(league_id, season, rank)
    """)

    op.execute("""
        CREATE INDEX idx_standings_updated
        ON standings(updated_at DESC)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE standings IS
        'League standings from API-Football (team positions, points, form)'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.league_id IS
        'API-Football league ID (e.g., 39 = Premier League)'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.season IS
        '4-digit season year (2024, 2025) representing season start'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.team_id IS
        'API-Football team ID'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.rank IS
        'Current position in league table (1 = first place)'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.form IS
        'Recent form string: W=Win, D=Draw, L=Loss (e.g., WWDWL)'
    """)

    op.execute("""
        COMMENT ON COLUMN standings.description IS
        'Qualification/relegation info (e.g., "UEFA Champions League - Group Stage")'
    """)


def downgrade() -> None:
    """Revert migration: Drop standings table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_standings_updated')
    op.execute('DROP INDEX IF EXISTS idx_standings_rank')
    op.execute('DROP INDEX IF EXISTS idx_standings_team')
    op.execute('DROP INDEX IF EXISTS idx_standings_league_season')

    # Drop table
    op.execute('DROP TABLE IF EXISTS standings CASCADE')
