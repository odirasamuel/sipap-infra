"""Add team_statistics table for team performance data

Revision ID: 20260806_006
Revises: 20260806_005
Create Date: 2026-08-06

Creates the team_statistics table to store detailed team performance statistics from
API-Football. Tracks home/away/total splits for matches, wins, draws, losses, goals,
clean sheets, and failed to score counts.

Schema Design:
- team_id: API-Football team ID
- league_id: API-Football league ID
- season: 4-digit season year (2024, 2025, etc.)
- Statistics split by venue: home, away, total
  * matches_played
  * wins, draws, losses
  * goals_for, goals_against
  * clean_sheets (matches without conceding)
  * failed_to_score (matches without scoring)

Unique constraint: (team_id, league_id, season) - one row per team per league-season

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_006'
down_revision = '20260806_005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create team_statistics table"""

    # Create team_statistics table
    op.execute("""
        CREATE TABLE team_statistics (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            team_id INT NOT NULL,
            league_id INT NOT NULL,
            season VARCHAR(4) NOT NULL,
            matches_played_home INT,
            matches_played_away INT,
            matches_played_total INT,
            wins_home INT,
            wins_away INT,
            wins_total INT,
            draws_home INT,
            draws_away INT,
            draws_total INT,
            losses_home INT,
            losses_away INT,
            losses_total INT,
            goals_for_home INT,
            goals_for_away INT,
            goals_for_total INT,
            goals_against_home INT,
            goals_against_away INT,
            goals_against_total INT,
            clean_sheets_home INT,
            clean_sheets_away INT,
            clean_sheets_total INT,
            failed_to_score_home INT,
            failed_to_score_away INT,
            failed_to_score_total INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            UNIQUE(team_id, league_id, season)
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_team_statistics_team
        ON team_statistics(team_id)
    """)

    op.execute("""
        CREATE INDEX idx_team_statistics_league_season
        ON team_statistics(league_id, season)
    """)

    op.execute("""
        CREATE INDEX idx_team_statistics_updated
        ON team_statistics(updated_at DESC)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE team_statistics IS
        'Team performance statistics from API-Football (home/away/total splits)'
    """)

    op.execute("""
        COMMENT ON COLUMN team_statistics.team_id IS
        'API-Football team ID'
    """)

    op.execute("""
        COMMENT ON COLUMN team_statistics.league_id IS
        'API-Football league ID (team stats are league-specific)'
    """)

    op.execute("""
        COMMENT ON COLUMN team_statistics.season IS
        '4-digit season year (2024, 2025) representing season start'
    """)

    op.execute("""
        COMMENT ON COLUMN team_statistics.clean_sheets_home IS
        'Matches at home without conceding a goal'
    """)

    op.execute("""
        COMMENT ON COLUMN team_statistics.failed_to_score_home IS
        'Matches at home without scoring a goal'
    """)


def downgrade() -> None:
    """Revert migration: Drop team_statistics table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_team_statistics_updated')
    op.execute('DROP INDEX IF EXISTS idx_team_statistics_league_season')
    op.execute('DROP INDEX IF EXISTS idx_team_statistics_team')

    # Drop table
    op.execute('DROP TABLE IF EXISTS team_statistics CASCADE')
