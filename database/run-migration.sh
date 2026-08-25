#!/bin/bash
set -e

echo "====================================="
echo "SIPAP Database Migration Script"
echo "Using Alembic for version-controlled migrations"
echo "====================================="

# Environment variables (passed from ECS task)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-sipap_dev}"
DB_USER="${DB_USER:-sipap_admin}"
SECRET_ARN="${SECRET_ARN}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Database Host: $DB_HOST"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"

# Get database credentials from Secrets Manager (JSON format)
echo ""
echo "Retrieving database credentials from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text)

if [ -z "$SECRET_JSON" ]; then
    echo "ERROR: Failed to retrieve database credentials"
    exit 1
fi

# Parse JSON to extract password (secret contains: username, password, host, port, database)
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" = "null" ]; then
    echo "ERROR: Failed to extract password from credentials JSON"
    exit 1
fi

echo "Credentials retrieved successfully"

# Export DB_PASSWORD for Alembic env.py
export DB_PASSWORD
export PGPASSWORD="$DB_PASSWORD"

# Wait for database to be ready
echo ""
echo "Waiting for database to be ready..."
until psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; do
    echo "Database is unavailable - sleeping"
    sleep 2
done

echo "Database is ready!"

# Check current migration status
echo ""
echo "====================================="
echo "Checking migration status..."
echo "====================================="

# Check if alembic_version table exists
ALEMBIC_TABLE_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name = 'alembic_version'
);
" | tr -d ' ')

if [ "$ALEMBIC_TABLE_EXISTS" = "t" ]; then
    CURRENT_VERSION=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT version_num FROM alembic_version;
    " | tr -d ' ')

    if [ -n "$CURRENT_VERSION" ]; then
        echo "Current migration version: $CURRENT_VERSION"
    else
        echo "No migrations applied yet (fresh database)"
    fi
else
    echo "Fresh database - checking if tables already exist from legacy migration..."

    # Check if users table exists (indicator that old migration ran)
    USERS_TABLE_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
    SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'users'
    );
    " | tr -d ' ')

    if [ "$USERS_TABLE_EXISTS" = "t" ]; then
        echo "⚠️  Tables already exist from legacy migration!"
        echo "Stamping baseline migration (20260614_001) as applied..."

        cd /migrations
        alembic stamp 20260614_001

        if [ $? -eq 0 ]; then
            echo "✅ Baseline migration stamped successfully"
            echo "Database is now under Alembic version control"
        else
            echo "❌ ERROR: Failed to stamp baseline migration"
            exit 1
        fi
    else
        echo "No existing tables found - will run migrations from scratch"
    fi
fi

# Run Alembic migrations
echo ""
echo "====================================="
echo "Running Alembic migrations..."
echo "====================================="

cd /migrations

# Show pending migrations
echo "Pending migrations:"
alembic history

echo ""
echo "Applying migrations..."
alembic upgrade head

if [ $? -eq 0 ]; then
    echo "✅ Migrations applied successfully!"
else
    echo "❌ ERROR: Migration failed"
    exit 1
fi

# Get final migration version
FINAL_VERSION=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT version_num FROM alembic_version;
" | tr -d ' ')

echo "Final migration version: $FINAL_VERSION"

# Verify database schema
echo ""
echo "====================================="
echo "Verifying database schema..."
echo "====================================="
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    tablename
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
"

# Count tables (should be 20 application tables + 1 alembic_version)
# Original 10: users, sports, leagues, teams, matches, predictions, prediction_evidence, agent_contributions, user_feedback, subscription_events
# Migrations 004-010: odds, standings, team_statistics, head_to_head, injuries, lineups, teams_metadata (7 tables)
# Migrations 013-014: subscription_plans, user_registration_tokens, payment_attempts (3 tables)
# Total: 10 + 7 + 3 = 20 tables
TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT COUNT(*)
FROM pg_tables
WHERE schemaname = 'public'
AND tablename != 'alembic_version';
" | tr -d ' ')

echo ""
echo "====================================="
echo "Migration Summary:"
echo "====================================="
echo "Migration Version: $FINAL_VERSION"
echo "Application Tables: $TABLE_COUNT"
echo "Expected Tables: 20"

if [ "$TABLE_COUNT" -ge 20 ]; then
    echo "✅ All tables created successfully!"
    exit 0
else
    echo "⚠️  Warning: Expected at least 20 tables but found $TABLE_COUNT"
    exit 1
fi
