# API-Football Database Migration Strategy

**Date:** 2026-08-06
**Phase:** Week 0 - Phase 3 (Database Migration)
**Status:** Migrations Created ✅ - Ready for Testing

---

## Executive Summary

Created 8 Alembic migrations to support API-Football single-source architecture consolidation. These migrations add new tables for expanded data types and prepare the matches table for transition from multi-source to single-source.

**Migration Numbers:** 004-011 (following existing 001-003)
**Approach:** Non-destructive (adds new columns/tables without removing old ones)
**Rollback:** All migrations have downgrade() functions for safe rollback

---

## Migration Files Created

### 1. Migration 004: Add Odds Table
**File:** `alembic/versions/20260806_004_add_odds_table.py`

**Purpose:** Store betting odds from API-Football (currently no odds table exists)

**Schema:**
- `fixture_id` (INT): API-Football fixture ID
- `bookmaker_id` (INT): API-Football bookmaker ID
- `bookmaker_name` (VARCHAR): Bookmaker name (Bet365, William Hill, etc.)
- `market` (VARCHAR): Market type (1X2, BTTS, Over/Under)
- `home_odds`, `draw_odds`, `away_odds` (DECIMAL)
- `over_under_value`, `over_odds`, `under_odds` (DECIMAL): For O/U markets
- `is_live` (BOOLEAN): Pre-match vs in-play odds
- UNIQUE constraint: `(fixture_id, bookmaker_id, market, is_live)`

**Indexes:** fixture_id, bookmaker_name, market, updated_at

### 2. Migration 005: Add Standings Table
**File:** `alembic/versions/20260806_005_add_standings_table.py`

**Purpose:** Store league standings from API-Football

**Schema:**
- `league_id` (INT): API-Football league ID (e.g., 39 = Premier League)
- `season` (VARCHAR 4): Season year (2024, 2025)
- `team_id` (INT): API-Football team ID
- `team_name` (VARCHAR): Team name
- `rank` (INT): Position in league table
- `points`, `matches_played`, `wins`, `draws`, `losses` (INT)
- `goals_for`, `goals_against`, `goal_difference` (INT)
- `form` (VARCHAR 10): Recent form string (WWDWL)
- `description` (VARCHAR): Qualification info (e.g., "UEFA Champions League")
- UNIQUE constraint: `(league_id, season, team_id)`

**Indexes:** (league_id, season), team_id, (league_id, season, rank), updated_at

### 3. Migration 006: Add Team Statistics Table
**File:** `alembic/versions/20260806_006_add_team_statistics_table.py`

**Purpose:** Store detailed team performance statistics

**Schema:**
- `team_id` (INT): API-Football team ID
- `league_id` (INT): API-Football league ID
- `season` (VARCHAR 4): Season year
- Statistics split by venue (home/away/total):
  - `matches_played_*`
  - `wins_*`, `draws_*`, `losses_*`
  - `goals_for_*`, `goals_against_*`
  - `clean_sheets_*` (matches without conceding)
  - `failed_to_score_*` (matches without scoring)
- UNIQUE constraint: `(team_id, league_id, season)`

**Indexes:** team_id, (league_id, season), updated_at

### 4. Migration 007: Add Head-to-Head Table
**File:** `alembic/versions/20260806_007_add_head_to_head_table.py`

**Purpose:** Store historical head-to-head records between teams

**Schema:**
- `team_1_id`, `team_2_id` (INT): API-Football team IDs
- `last_10_matches` (JSONB): Array of last 10 H2H results
- `team_1_wins`, `draws`, `team_2_wins` (INT): Overall H2H record
- UNIQUE constraint: `(team_1_id, team_2_id)`
- CHECK constraint: `team_1_id < team_2_id` (ensures consistent ordering)

**Indexes:** team_1_id, team_2_id, updated_at

### 5. Migration 008: Add Injuries Table
**File:** `alembic/versions/20260806_008_add_injuries_table.py`

**Purpose:** Store player injury data

**Schema:**
- `fixture_id` (INT): API-Football fixture ID
- `team_id` (INT): API-Football team ID
- `player_id` (INT): API-Football player ID
- `player_name`, `player_position` (VARCHAR)
- `injury_type`, `injury_reason` (VARCHAR): e.g., "Knee Injury", "Suspended"
- `expected_return_date` (DATE): When player returns (NULL if unknown)
- UNIQUE constraint: `(fixture_id, player_id)`

**Indexes:** fixture_id, team_id, player_id, expected_return_date

### 6. Migration 009: Add Lineups Table
**File:** `alembic/versions/20260806_009_add_lineups_table.py`

**Purpose:** Store match starting lineups and formations

**Schema:**
- `fixture_id` (INT): API-Football fixture ID (UNIQUE)
- `home_team_id`, `away_team_id` (INT): API-Football team IDs
- `home_formation`, `away_formation` (VARCHAR 10): e.g., "4-3-3", "4-4-2"
- `home_lineup`, `away_lineup` (JSONB): Starting XI arrays
- `home_substitutes`, `away_substitutes` (JSONB): Bench players
- `home_coach`, `away_coach` (VARCHAR): Coach names
- UNIQUE constraint: `fixture_id`

**Indexes:** fixture_id, home_team_id, away_team_id, (home_formation, away_formation)

### 7. Migration 010: Add Teams Metadata Table
**File:** `alembic/versions/20260806_010_add_teams_metadata_table.py`

**Purpose:** Store detailed team information

**Schema:**
- `team_id` (INT): API-Football team ID (UNIQUE)
- `name` (VARCHAR): Team name
- `code` (VARCHAR 10): Short code (ARS, CHE, MUN, etc.)
- `country` (VARCHAR): Team country
- `founded` (INT): Year founded
- `national` (BOOLEAN): National team vs club team
- `logo_url` (VARCHAR): Team logo URL
- `venue_id`, `venue_name`, `venue_city`, `venue_capacity`, `venue_surface`: Stadium info
- UNIQUE constraint: `team_id`

**Indexes:** team_id, name, country, national (partial index for true values)

### 8. Migration 011: Update Matches for API-Football ⚠️ CRITICAL
**File:** `alembic/versions/20260806_011_update_matches_for_api_football.py`

**Purpose:** Prepare matches table for API-Football single-source transition

**Changes:**
- **ADD** `fixture_id` (INT): API-Football fixture ID (will become primary identifier)
- **ADD** `league_api_id` (INT): API-Football league ID (e.g., 39 = Premier League)
- **ADD** `season` (VARCHAR 4): Season year (2024, 2025)
- **ADD** `round` (VARCHAR 50): Match round (e.g., "Regular Season - 1", "Final")
- **ADD** `referee` (VARCHAR): Referee name
- **DEPRECATE** `source` column (marked in comment as deprecated)
- **DEPRECATE** `external_id` column (marked in comment as deprecated)
- **KEEP** denormalized columns (home_team, away_team, league) for backward compatibility

**Indexes:** fixture_id, (league_api_id, season)

**Migration Strategy:**
- Non-destructive: Adds new columns without removing old ones
- Allows gradual transition: old batch jobs still work
- Future migration (after backfill) will remove source/external_id

---

## Migration Dependencies

```
20260614_001_initial_schema.py (initial)
  ↓
20260804_002_add_denormalized_columns_to_matches.py
  ↓
20260804_003_add_statistical_indexes_to_matches.py
  ↓
20260806_004_add_odds_table.py ← NEW
  ↓
20260806_005_add_standings_table.py ← NEW
  ↓
20260806_006_add_team_statistics_table.py ← NEW
  ↓
20260806_007_add_head_to_head_table.py ← NEW
  ↓
20260806_008_add_injuries_table.py ← NEW
  ↓
20260806_009_add_lineups_table.py ← NEW
  ↓
20260806_010_add_teams_metadata_table.py ← NEW
  ↓
20260806_011_update_matches_for_api_football.py ← NEW (CRITICAL)
```

---

## How to Run Migrations

### Development Environment (Local)

**Prerequisites:**
- Docker installed and running
- PostgreSQL running locally (or via Docker)
- Alembic configured (`alembic.ini` already set up)

**Steps:**

1. **Navigate to database directory:**
   ```bash
   cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/database
   ```

2. **Check current migration status:**
   ```bash
   alembic current
   # Should show: 20260804_003 (head)
   ```

3. **View pending migrations:**
   ```bash
   alembic history
   # Should show migrations 004-011 as pending
   ```

4. **Upgrade to latest (apply all 8 new migrations):**
   ```bash
   alembic upgrade head
   ```

5. **Verify migrations applied:**
   ```bash
   alembic current
   # Should show: 20260806_011 (head)
   ```

6. **Check database tables:**
   ```bash
   psql -h localhost -U sipap_admin -d sipap_dev -c "\dt"
   # Should see: odds, standings, team_statistics, head_to_head, injuries, lineups, teams_metadata
   ```

### Production Environment (AWS)

**Option 1: ECS Fargate Migration Container (Recommended)**

Use existing migration infrastructure:
```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform
./database/deploy-and-run-migrations.sh
```

**Option 2: Manual Deployment**

See `database/README.md` for detailed ECS Fargate deployment instructions.

---

## Rollback Instructions

### Rollback One Migration

```bash
alembic downgrade -1
```

### Rollback to Specific Version

```bash
# Rollback to migration 003 (before new migrations)
alembic downgrade 20260804_003
```

### Rollback All New Migrations

```bash
# Rollback from 011 to 003 (removes all 8 new migrations)
alembic downgrade 20260804_003
```

---

## Testing Strategy

### 1. Syntax Validation ✅

**Test:** Alembic can parse all migration files
```bash
alembic check
# Expected: No errors
```

### 2. Migration Upgrade Test

**Test:** Apply all migrations in sequence
```bash
# Start from 003
alembic upgrade 20260804_003

# Apply new migrations one by one
alembic upgrade 20260806_004  # Odds table
alembic upgrade 20260806_005  # Standings table
alembic upgrade 20260806_006  # Team statistics
alembic upgrade 20260806_007  # Head-to-head
alembic upgrade 20260806_008  # Injuries
alembic upgrade 20260806_009  # Lineups
alembic upgrade 20260806_010  # Teams metadata
alembic upgrade 20260806_011  # Matches updates

# Or apply all at once
alembic upgrade head
```

### 3. Migration Downgrade Test

**Test:** Rollback all migrations
```bash
# Rollback from 011 to 003
alembic downgrade 20260804_003

# Verify tables dropped
psql -h localhost -U sipap_admin -d sipap_dev -c "\dt"
# Should NOT see: odds, standings, team_statistics, head_to_head, injuries, lineups, teams_metadata
```

### 4. Data Integrity Test

**Test:** Verify constraints and indexes created
```bash
# Check unique constraints
psql -h localhost -U sipap_admin -d sipap_dev -c "
  SELECT conname, conrelid::regclass
  FROM pg_constraint
  WHERE conname LIKE '%odds%' OR conname LIKE '%standings%'
"

# Check indexes
psql -h localhost -U sipap_admin -d sipap_dev -c "
  SELECT indexname, tablename
  FROM pg_indexes
  WHERE tablename IN ('odds', 'standings', 'team_statistics')
"
```

---

## Next Steps (Phase 4)

**After migrations are applied:**

1. **Create 6 new batch jobs** (sipap-batch-scraper):
   - `standings_updater.py`: Fetch and store league standings
   - `team_stats_updater.py`: Fetch and store team statistics
   - `injuries_updater.py`: Fetch and store player injuries
   - `lineups_fetcher.py`: Fetch and store match lineups
   - `h2h_fetcher.py`: Fetch and store head-to-head records
   - `teams_metadata_sync.py`: Sync team metadata

2. **Update existing batch jobs**:
   - `daily_harvest.py`: Populate fixture_id field (already uses API-Football)
   - `api_football_odds_updater.py`: Use new odds table (currently no table)

3. **Historical backfill**:
   - Run backfill script to populate 6 seasons of historical data
   - See `api-football-implementation-plan.md` for backfill strategy

4. **Verify data quality**:
   - Check fixture_id population rate
   - Verify odds data integrity
   - Validate standings accuracy

---

## Risk Assessment

### Low Risk ⚠️

- **New tables:** odds, standings, team_statistics, head_to_head, injuries, lineups, teams_metadata
- **Reason:** Fresh tables, no existing data to migrate
- **Mitigation:** N/A (safe operation)

### Medium Risk ⚠️⚠️

- **Matches table updates:** Adding new columns (fixture_id, league_api_id, season, round, referee)
- **Reason:** Modifying existing table with production data
- **Mitigation:**
  - Non-destructive migration (adds columns, doesn't remove)
  - Old columns (source, external_id) remain functional
  - Gradual transition allows rollback if issues arise

### High Risk ⚠️⚠️⚠️

- **Future migration:** Removing source/external_id columns (NOT in this phase)
- **Reason:** Would break existing batch jobs if done prematurely
- **Mitigation:**
  - This migration NOT included in Phase 3
  - Will be done in future phase after backfill complete
  - Requires verification that all matches have fixture_id populated

---

## Success Criteria

**Migration Phase 3 Complete When:**

- ✅ All 8 migrations applied without errors
- ✅ All new tables created with correct schema
- ✅ All indexes and constraints created
- ✅ Matches table has new columns (fixture_id, league_api_id, season, round, referee)
- ✅ Old columns (source, external_id) remain intact
- ✅ No data loss or corruption
- ✅ Migrations can be rolled back successfully

**Verification Checklist:**

```bash
# 1. Check migration status
alembic current
# Expected: 20260806_011 (head)

# 2. Verify table count (should be 18 tables total)
psql -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'"
# Expected: 18 tables (10 original + 8 new)

# 3. Verify new tables exist
psql -c "\dt" | grep -E "odds|standings|team_statistics|head_to_head|injuries|lineups|teams_metadata"
# Expected: All 7 new tables listed

# 4. Verify matches table columns
psql -c "\d matches" | grep -E "fixture_id|league_api_id|season|round|referee"
# Expected: All 5 new columns listed

# 5. Check index count
psql -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public'"
# Expected: ~40+ indexes (original + new migrations)
```

---

## Document Version

**Version:** 1.0
**Created:** 2026-08-06
**Author:** SIPAP Development Team
**Status:** Migrations Created - Ready for Testing

---

**END OF DOCUMENT**
