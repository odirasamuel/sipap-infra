"""Update matches table for API-Football single-source consolidation

Revision ID: 20260806_011
Revises: 20260806_010
Create Date: 2026-08-06

Updates the matches table to support API-Football as the single source of truth.
This migration is part of Phase 3: Database Migration for API-Football consolidation.

Changes:
1. ADD fixture_id column (API-Football fixture ID - will become primary identifier)
2. ADD league_api_id and season columns (API-Football league ID and season)
3. DEPRECATE source column (mark for future removal after backfill complete)
4. KEEP denormalized columns (home_team, away_team, league) for backward compatibility
5. ADD new columns: round, referee (API-Football provides these)

Migration Strategy:
- Non-destructive: Adds new columns without removing old ones
- Allows gradual transition: old batch jobs still work, new jobs use fixture_id
- Future migration (after backfill) will remove source/external_id

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_011'
down_revision = '20260806_010'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Update matches table for API-Football"""

    # Add new columns for API-Football
    op.execute("""
        ALTER TABLE matches
        ADD COLUMN IF NOT EXISTS fixture_id INT,
        ADD COLUMN IF NOT EXISTS league_api_id INT,
        ADD COLUMN IF NOT EXISTS season VARCHAR(4),
        ADD COLUMN IF NOT EXISTS round VARCHAR(50),
        ADD COLUMN IF NOT EXISTS referee VARCHAR(255)
    """)

    # Create index on fixture_id (will be unique after backfill)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_matches_fixture_id
        ON matches(fixture_id)
    """)

    # Create index on league_api_id and season
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_matches_league_season
        ON matches(league_api_id, season)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON COLUMN matches.fixture_id IS
        'API-Football fixture ID (will become primary identifier after consolidation)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.league_api_id IS
        'API-Football league ID (e.g., 39 = Premier League)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.season IS
        '4-digit season year (2024, 2025) representing season start'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.round IS
        'Match round/week (e.g., "Regular Season - 1", "Final", "Quarter-finals")'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.referee IS
        'Match referee name from API-Football'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.source IS
        'DEPRECATED: Data source identifier. Use fixture_id instead. Will be removed after consolidation.'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.external_id IS
        'DEPRECATED: External match ID from various sources. Use fixture_id instead. Will be removed after consolidation.'
    """)

    # Add table comment documenting the transition
    op.execute("""
        COMMENT ON TABLE matches IS
        'Match fixtures and results. Transitioning to API-Football single-source (fixture_id). Legacy fields (source, external_id) deprecated.'
    """)


def downgrade() -> None:
    """Revert migration: Remove API-Football columns"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_matches_league_season')
    op.execute('DROP INDEX IF EXISTS idx_matches_fixture_id')

    # Drop columns
    op.execute("""
        ALTER TABLE matches
        DROP COLUMN IF EXISTS referee,
        DROP COLUMN IF EXISTS round,
        DROP COLUMN IF EXISTS season,
        DROP COLUMN IF EXISTS league_api_id,
        DROP COLUMN IF EXISTS fixture_id
    """)

    # Restore original table comment
    op.execute("""
        COMMENT ON TABLE matches IS
        'Match fixtures and results from multiple sources'
    """)

    # Remove deprecation comments
    op.execute("""
        COMMENT ON COLUMN matches.source IS
        'Data source identifier (football-data.org, thesportsdb, etc.)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.external_id IS
        'External match ID from data source'
    """)
