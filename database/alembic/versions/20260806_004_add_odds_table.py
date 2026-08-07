"""Add odds table for API-Football

Revision ID: 20260806_004
Revises: 20260804_003
Create Date: 2026-08-06

Creates the odds table to store betting odds from API-Football. This table is aligned
with API-Football's data structure and supports:
- Multiple bookmakers per fixture
- Multiple markets (1X2, BTTS, Over/Under)
- Pre-match and live odds (is_live flag)
- Bookmaker IDs from API-Football

Schema Design:
- fixture_id: API-Football fixture ID (references matches after consolidation)
- bookmaker_id: API-Football bookmaker ID
- bookmaker_name: Bookmaker name (Bet365, William Hill, etc.)
- market: Market type (1X2, BTTS, Over/Under)
- home_odds, draw_odds, away_odds: Main market odds
- over_under_value: For O/U markets (2.5, 3.5, etc.)
- over_odds, under_odds: For O/U markets
- is_live: Pre-match (false) vs in-play (true)

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20260806_004'
down_revision = '20260804_003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Apply migration: Create odds table"""

    # Create odds table
    op.execute("""
        CREATE TABLE odds (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            fixture_id INT NOT NULL,
            bookmaker_id INT NOT NULL,
            bookmaker_name VARCHAR(255) NOT NULL,
            market VARCHAR(50) NOT NULL,
            home_odds DECIMAL(5,2),
            draw_odds DECIMAL(5,2),
            away_odds DECIMAL(5,2),
            over_under_value DECIMAL(3,1),
            over_odds DECIMAL(5,2),
            under_odds DECIMAL(5,2),
            is_live BOOLEAN DEFAULT FALSE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            UNIQUE(fixture_id, bookmaker_id, market, is_live)
        )
    """)

    # Create indexes for faster queries
    op.execute("""
        CREATE INDEX idx_odds_fixture
        ON odds(fixture_id)
    """)

    op.execute("""
        CREATE INDEX idx_odds_bookmaker
        ON odds(bookmaker_name)
    """)

    op.execute("""
        CREATE INDEX idx_odds_market
        ON odds(market)
    """)

    op.execute("""
        CREATE INDEX idx_odds_updated
        ON odds(updated_at DESC)
    """)

    # Add column comments
    op.execute("""
        COMMENT ON TABLE odds IS
        'Betting odds from API-Football (multiple bookmakers, markets)'
    """)

    op.execute("""
        COMMENT ON COLUMN odds.fixture_id IS
        'API-Football fixture ID (will reference matches.fixture_id after consolidation)'
    """)

    op.execute("""
        COMMENT ON COLUMN odds.bookmaker_id IS
        'API-Football bookmaker ID (numeric identifier)'
    """)

    op.execute("""
        COMMENT ON COLUMN odds.market IS
        'Market type: 1X2, BTTS (Both Teams To Score), Over/Under'
    """)

    op.execute("""
        COMMENT ON COLUMN odds.is_live IS
        'Pre-match odds (false) vs in-play/live odds (true)'
    """)


def downgrade() -> None:
    """Revert migration: Drop odds table"""

    # Drop indexes
    op.execute('DROP INDEX IF EXISTS idx_odds_updated')
    op.execute('DROP INDEX IF EXISTS idx_odds_market')
    op.execute('DROP INDEX IF EXISTS idx_odds_bookmaker')
    op.execute('DROP INDEX IF EXISTS idx_odds_fixture')

    # Drop table
    op.execute('DROP TABLE IF EXISTS odds CASCADE')
