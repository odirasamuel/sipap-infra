-- Migration: Add denormalized columns to matches table for batch scraper
-- Date: 2026-06-29
-- Reason: Batch scraper needs to store match data without requiring
--         team/league lookups. These denormalized columns coexist with
--         the normalized foreign keys for future use.

-- Add denormalized columns to matches table
ALTER TABLE matches
ADD COLUMN IF NOT EXISTS home_team VARCHAR(200),
ADD COLUMN IF NOT EXISTS away_team VARCHAR(200),
ADD COLUMN IF NOT EXISTS league VARCHAR(200),
ADD COLUMN IF NOT EXISTS source VARCHAR(50);

-- Create index on source for faster queries
CREATE INDEX IF NOT EXISTS idx_matches_source ON matches(source);

-- Update UNIQUE constraint to include source
-- (external_id alone isn't unique across sources)
ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_sport_id_external_id_key;
ALTER TABLE matches ADD CONSTRAINT matches_external_id_source_unique
    UNIQUE (external_id, source);

-- Comment
COMMENT ON COLUMN matches.home_team IS 'Denormalized home team name from API (for MVP batch scraper)';
COMMENT ON COLUMN matches.away_team IS 'Denormalized away team name from API (for MVP batch scraper)';
COMMENT ON COLUMN matches.league IS 'Denormalized league name from API (for MVP batch scraper)';
COMMENT ON COLUMN matches.source IS 'Data source identifier (football-data.org, thesportsdb, etc.)';
