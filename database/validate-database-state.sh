#!/bin/bash
set -e

echo "=========================================="
echo "SIPAP Database State Validation"
echo "=========================================="
echo ""

# Environment variables
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"

# Check if required vars are set
if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "❌ ERROR: Missing required environment variables"
    echo "Required: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD"
    echo ""
    echo "Usage:"
    echo "  export DB_HOST='your-rds-endpoint'"
    echo "  export DB_NAME='sipap_dev'"
    echo "  export DB_USER='sipap_admin'"
    echo "  export DB_PASSWORD='your-password'"
    echo "  ./validate-database-state.sh"
    exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

echo "Database Host: $DB_HOST"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo ""

# Test connection
echo "Testing database connection..."
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
    echo "❌ ERROR: Cannot connect to database"
    exit 1
fi
echo "✅ Database connection successful"
echo ""

# Check Alembic version
echo "=========================================="
echo "1. Alembic Migration Status"
echo "=========================================="

ALEMBIC_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'alembic_version'
);" | tr -d ' ')

if [ "$ALEMBIC_EXISTS" = "t" ]; then
    CURRENT_VERSION=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT version_num FROM alembic_version;" | tr -d ' ')

    if [ -n "$CURRENT_VERSION" ]; then
        echo "✅ Alembic is active"
        echo "   Current version: $CURRENT_VERSION"
    else
        echo "⚠️  Alembic table exists but no version recorded"
    fi
else
    echo "⚠️  Alembic not initialized (no alembic_version table)"
fi
echo ""

# Check matches table structure
echo "=========================================="
echo "2. Matches Table Structure"
echo "=========================================="

MATCHES_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'matches'
);" | tr -d ' ')

if [ "$MATCHES_EXISTS" = "t" ]; then
    echo "✅ 'matches' table exists"
    echo ""
    echo "Columns in matches table:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    SELECT
        column_name,
        data_type,
        character_maximum_length,
        is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'matches'
    ORDER BY ordinal_position;"

    # Check for denormalized columns
    echo ""
    echo "Checking for denormalized columns (from migration 001):"

    HOME_TEAM_COL=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'matches' AND column_name = 'home_team'
    );" | tr -d ' ')

    AWAY_TEAM_COL=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'matches' AND column_name = 'away_team'
    );" | tr -d ' ')

    LEAGUE_COL=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'matches' AND column_name = 'league'
    );" | tr -d ' ')

    SOURCE_COL=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'matches' AND column_name = 'source'
    );" | tr -d ' ')

    if [ "$HOME_TEAM_COL" = "t" ]; then
        echo "  ✅ home_team column exists"
    else
        echo "  ❌ home_team column MISSING"
    fi

    if [ "$AWAY_TEAM_COL" = "t" ]; then
        echo "  ✅ away_team column exists"
    else
        echo "  ❌ away_team column MISSING"
    fi

    if [ "$LEAGUE_COL" = "t" ]; then
        echo "  ✅ league column exists"
    else
        echo "  ❌ league column MISSING"
    fi

    if [ "$SOURCE_COL" = "t" ]; then
        echo "  ✅ source column exists"
    else
        echo "  ❌ source column MISSING"
    fi

else
    echo "❌ 'matches' table DOES NOT exist"
fi
echo ""

# Check fixtures table (should NOT exist)
echo "=========================================="
echo "3. Fixtures Table Check"
echo "=========================================="

FIXTURES_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'fixtures'
);" | tr -d ' ')

if [ "$FIXTURES_EXISTS" = "t" ]; then
    echo "⚠️  'fixtures' table EXISTS (unexpected!)"
    echo "   This may indicate a naming conflict or separate table."
else
    echo "✅ 'fixtures' table does NOT exist (expected)"
fi
echo ""

# Check existing indexes on matches table
echo "=========================================="
echo "4. Existing Indexes on Matches Table"
echo "=========================================="

if [ "$MATCHES_EXISTS" = "t" ]; then
    echo "Current indexes:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    SELECT
        indexname,
        indexdef
    FROM pg_indexes
    WHERE tablename = 'matches'
    ORDER BY indexname;"

    echo ""
    echo "Checking for statistical indexes (from upcoming migration 002):"

    # Check each statistical index
    IDX_H2H_HOME_AWAY=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_h2h_home_away'
    );" | tr -d ' ')

    IDX_H2H_AWAY_HOME=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_h2h_away_home'
    );" | tr -d ' ')

    IDX_TEAM_HOME=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_team_home_league'
    );" | tr -d ' ')

    IDX_TEAM_AWAY=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_team_away_league'
    );" | tr -d ' ')

    IDX_HALFTIME=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_metadata_halftime'
    );" | tr -d ' ')

    IDX_LEAGUE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM pg_indexes
        WHERE tablename = 'matches' AND indexname = 'idx_matches_league_scheduled'
    );" | tr -d ' ')

    echo ""
    if [ "$IDX_H2H_HOME_AWAY" = "t" ]; then
        echo "  ✅ idx_matches_h2h_home_away EXISTS"
    else
        echo "  ❌ idx_matches_h2h_home_away MISSING (will be created)"
    fi

    if [ "$IDX_H2H_AWAY_HOME" = "t" ]; then
        echo "  ✅ idx_matches_h2h_away_home EXISTS"
    else
        echo "  ❌ idx_matches_h2h_away_home MISSING (will be created)"
    fi

    if [ "$IDX_TEAM_HOME" = "t" ]; then
        echo "  ✅ idx_matches_team_home_league EXISTS"
    else
        echo "  ❌ idx_matches_team_home_league MISSING (will be created)"
    fi

    if [ "$IDX_TEAM_AWAY" = "t" ]; then
        echo "  ✅ idx_matches_team_away_league EXISTS"
    else
        echo "  ❌ idx_matches_team_away_league MISSING (will be created)"
    fi

    if [ "$IDX_HALFTIME" = "t" ]; then
        echo "  ✅ idx_matches_metadata_halftime EXISTS"
    else
        echo "  ❌ idx_matches_metadata_halftime MISSING (will be created)"
    fi

    if [ "$IDX_LEAGUE" = "t" ]; then
        echo "  ✅ idx_matches_league_scheduled EXISTS"
    else
        echo "  ❌ idx_matches_league_scheduled MISSING (will be created)"
    fi
fi
echo ""

# Check sample data
echo "=========================================="
echo "5. Sample Data Check"
echo "=========================================="

if [ "$MATCHES_EXISTS" = "t" ]; then
    ROW_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT COUNT(*) FROM matches;" | tr -d ' ')

    echo "Total matches in database: $ROW_COUNT"

    if [ "$ROW_COUNT" -gt 0 ]; then
        echo ""
        echo "Sample matches (first 5):"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT
            id,
            home_team,
            away_team,
            league,
            scheduled_at,
            status,
            source
        FROM matches
        ORDER BY scheduled_at DESC
        LIMIT 5;"

        echo ""
        echo "Matches with halftime data:"
        HALFTIME_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*)
        FROM matches
        WHERE metadata ? 'halftime_home_score';" | tr -d ' ')

        echo "  Count: $HALFTIME_COUNT / $ROW_COUNT"
        if [ "$HALFTIME_COUNT" -gt 0 ]; then
            HALFTIME_PCT=$(echo "scale=2; $HALFTIME_COUNT * 100 / $ROW_COUNT" | bc)
            echo "  Percentage: ${HALFTIME_PCT}%"
        fi
    fi
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "6. Summary & Recommendations"
echo "=========================================="

echo ""
echo "Database State:"
if [ "$MATCHES_EXISTS" = "t" ]; then
    echo "  ✅ matches table exists"
else
    echo "  ❌ matches table MISSING"
fi

if [ "$FIXTURES_EXISTS" = "t" ]; then
    echo "  ⚠️  fixtures table exists (naming conflict!)"
else
    echo "  ✅ fixtures table does not exist"
fi

if [ "$ALEMBIC_EXISTS" = "t" ] && [ -n "$CURRENT_VERSION" ]; then
    echo "  ✅ Alembic version control active (version: $CURRENT_VERSION)"
else
    echo "  ⚠️  Alembic not properly initialized"
fi

echo ""
echo "Migration 001 (Denormalized Columns):"
if [ "$HOME_TEAM_COL" = "t" ] && [ "$AWAY_TEAM_COL" = "t" ] && [ "$LEAGUE_COL" = "t" ]; then
    echo "  ✅ Already applied (columns exist)"
else
    echo "  ❌ NOT applied (columns missing)"
fi

echo ""
echo "Migration 002 (Statistical Indexes):"
INDEXES_COUNT=0
[ "$IDX_H2H_HOME_AWAY" = "t" ] && ((INDEXES_COUNT++))
[ "$IDX_H2H_AWAY_HOME" = "t" ] && ((INDEXES_COUNT++))
[ "$IDX_TEAM_HOME" = "t" ] && ((INDEXES_COUNT++))
[ "$IDX_TEAM_AWAY" = "t" ] && ((INDEXES_COUNT++))
[ "$IDX_HALFTIME" = "t" ] && ((INDEXES_COUNT++))
[ "$IDX_LEAGUE" = "t" ] && ((INDEXES_COUNT++))

if [ "$INDEXES_COUNT" -eq 6 ]; then
    echo "  ✅ Already applied (all 6 indexes exist)"
elif [ "$INDEXES_COUNT" -eq 0 ]; then
    echo "  ❌ NOT applied (no indexes exist)"
    echo "  → Safe to run migration 002"
else
    echo "  ⚠️  Partially applied ($INDEXES_COUNT/6 indexes exist)"
    echo "  → Migration 002 will create missing indexes (idempotent)"
fi

echo ""
echo "=========================================="
echo "Validation Complete"
echo "=========================================="
