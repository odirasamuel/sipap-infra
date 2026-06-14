-- SIPAP Seed Data
-- Insert initial sports and leagues for MVP

-- Seed sports
INSERT INTO sports (name, display_name, enabled) VALUES
    ('soccer', 'Soccer', true),
    ('nba', 'NBA Basketball', false),
    ('nfl', 'NFL Football', false),
    ('tennis', 'Tennis', false);

-- Seed soccer leagues (MVP)
INSERT INTO leagues (sport_id, external_id, name, country, tier, enabled)
SELECT s.id, 'EPL', 'Premier League', 'England', 1, true
FROM sports s WHERE s.name = 'soccer';

INSERT INTO leagues (sport_id, external_id, name, country, tier, enabled)
SELECT s.id, 'LALIGA', 'La Liga', 'Spain', 1, true
FROM sports s WHERE s.name = 'soccer';

INSERT INTO leagues (sport_id, external_id, name, country, tier, enabled)
SELECT s.id, 'BUNDESLIGA', 'Bundesliga', 'Germany', 1, true
FROM sports s WHERE s.name = 'soccer';

INSERT INTO leagues (sport_id, external_id, name, country, tier, enabled)
SELECT s.id, 'SERIEA', 'Serie A', 'Italy', 1, true
FROM sports s WHERE s.name = 'soccer';

INSERT INTO leagues (sport_id, external_id, name, country, tier, enabled)
SELECT s.id, 'LIGUE1', 'Ligue 1', 'France', 1, true
FROM sports s WHERE s.name = 'soccer';
