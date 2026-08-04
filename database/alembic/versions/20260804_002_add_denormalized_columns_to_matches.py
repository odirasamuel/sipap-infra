"""Add denormalized columns to matches table

Revision ID: 20260804_002
Revises: 20260614_001
Create Date: 2026-08-04

Adds denormalized columns to the matches table for batch scraper and statistical
analysis tools. These columns store data directly from APIs without requiring
team/league lookups.

Columns Added:
- home_team (VARCHAR 200): Home team name from API
- away_team (VARCHAR 200): Away team name from API
- league (VARCHAR 200): League name from API
- source (VARCHAR 50): Data source identifier (football-data.org, thesportsdb, etc.)

These denormalized columns coexist with the normalized foreign keys (home_team_id,
away_team_id, league_id) for MVP development. Statistical tools use the denormalized
columns for fast text-based queries.

Note: This migration incorporates the logic from the orphaned SQL migration
      migrations/versions/001_add_denormalized_columns_to_matches.sql
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260804_002'
down_revision = '20260614_001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Add denormalized columns to matches table"""

    # Add denormalized columns
    op.execute("""
        ALTER TABLE matches
        ADD COLUMN IF NOT EXISTS home_team VARCHAR(200),
        ADD COLUMN IF NOT EXISTS away_team VARCHAR(200),
        ADD COLUMN IF NOT EXISTS league VARCHAR(200),
        ADD COLUMN IF NOT EXISTS source VARCHAR(50)
    """)

    # Create index on source for faster queries by data source
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_matches_source
        ON matches(source)
    """)

    # Update UNIQUE constraint to include source
    # (external_id alone isn't unique across different data sources)
    op.execute("""
        ALTER TABLE matches
        DROP CONSTRAINT IF EXISTS matches_sport_id_external_id_key
    """)

    op.execute("""
        ALTER TABLE matches
        ADD CONSTRAINT matches_external_id_source_unique
        UNIQUE (external_id, source)
    """)

    # Add column comments for documentation
    op.execute("""
        COMMENT ON COLUMN matches.home_team IS
        'Denormalized home team name from API (for MVP batch scraper)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.away_team IS
        'Denormalized away team name from API (for MVP batch scraper)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.league IS
        'Denormalized league name from API (for MVP batch scraper)'
    """)

    op.execute("""
        COMMENT ON COLUMN matches.source IS
        'Data source identifier (football-data.org, thesportsdb, etc.)'
    """)


def downgrade() -> None:
    """Revert migration: Remove denormalized columns"""

    # Drop constraint
    op.execute("""
        ALTER TABLE matches
        DROP CONSTRAINT IF EXISTS matches_external_id_source_unique
    """)

    # Restore original constraint
    op.execute("""
        ALTER TABLE matches
        ADD CONSTRAINT matches_sport_id_external_id_key
        UNIQUE (sport_id, external_id)
    """)

    # Drop index
    op.execute('DROP INDEX IF EXISTS idx_matches_source')

    # Drop columns
    op.execute("""
        ALTER TABLE matches
        DROP COLUMN IF EXISTS source,
        DROP COLUMN IF EXISTS league,
        DROP COLUMN IF EXISTS away_team,
        DROP COLUMN IF EXISTS home_team
    """)
