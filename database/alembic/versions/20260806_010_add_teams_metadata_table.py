"""Add teams_metadata table for team information

Revision ID: 20260806_010
Revises: 20260806_009
Create Date: 2026-08-06

Creates the teams_metadata table to store detailed team information from API-Football
including logos, venues, capacity, and founding information.

Schema Design:
- team_id: API-Football team ID (unique)
- name: Team name
- code: Short team code (ARS, CHE, MUN, etc.)
- country: Team country
- founded: Year team was founded
- national: Boolean flag for national teams vs clubs
- logo_url: Team logo URL
- venue_id, venue_name, venue_city, venue_capacity, venue_surface: Stadium information

Unique constraint: team_id (one row per team)

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_010'
down_revision = '20260806_009'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create teams_metadata table"""

    # Create teams_metadata table
    op.execute("""
        CREATE TABLE teams_metadata (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            team_id INT NOT NULL UNIQUE,
            name VARCHAR(255) NOT NULL,
            code VARCHAR(10),
            country VARCHAR(100),
            founded INT,
            national BOOLEAN,
            logo_url VARCHAR(500),
            venue_id INT,
            venue_name VARCHAR(255),
            venue_city VARCHAR(255),
            venue_capacity INT,
            venue_surface VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_teams_metadata_team_id
        ON teams_metadata(team_id)
    """)

    op.execute("""
        CREATE INDEX idx_teams_metadata_name
        ON teams_metadata(name)
    """)

    op.execute("""
        CREATE INDEX idx_teams_metadata_country
        ON teams_metadata(country)
    """)

    op.execute("""
        CREATE INDEX idx_teams_metadata_national
        ON teams_metadata(national)
        WHERE national = true
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE teams_metadata IS
        'Team metadata from API-Football (logos, venues, founding info)'
    """)

    op.execute("""
        COMMENT ON COLUMN teams_metadata.team_id IS
        'API-Football team ID (unique identifier)'
    """)

    op.execute("""
        COMMENT ON COLUMN teams_metadata.code IS
        'Short team code: ARS, CHE, MUN, LIV, etc.'
    """)

    op.execute("""
        COMMENT ON COLUMN teams_metadata.national IS
        'True for national teams, False for club teams'
    """)

    op.execute("""
        COMMENT ON COLUMN teams_metadata.venue_surface IS
        'Playing surface: grass, artificial turf, etc.'
    """)


def downgrade() -> None:
    """Revert migration: Drop teams_metadata table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_teams_metadata_national')
    op.execute('DROP INDEX IF EXISTS idx_teams_metadata_country')
    op.execute('DROP INDEX IF EXISTS idx_teams_metadata_name')
    op.execute('DROP INDEX IF EXISTS idx_teams_metadata_team_id')

    # Drop table
    op.execute('DROP TABLE IF EXISTS teams_metadata CASCADE')
