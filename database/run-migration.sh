#!/bin/bash
set -e

echo "====================================="
echo "SIPAP Database Migration Script"
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

# Get database password from Secrets Manager
echo ""
echo "Retrieving database password from Secrets Manager..."
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text)

if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: Failed to retrieve database password"
    exit 1
fi

echo "Password retrieved successfully"

# Set PGPASSWORD for psql
export PGPASSWORD="$DB_PASSWORD"

# Wait for database to be ready
echo ""
echo "Waiting for database to be ready..."
until psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; do
    echo "Database is unavailable - sleeping"
    sleep 2
done

echo "Database is ready!"

# Run schema migration
echo ""
echo "====================================="
echo "Running schema.sql migration..."
echo "====================================="
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f /migrations/schema.sql

if [ $? -eq 0 ]; then
    echo "Schema migration completed successfully!"
else
    echo "ERROR: Schema migration failed"
    exit 1
fi

# Run seed data migration
echo ""
echo "====================================="
echo "Running seed_data.sql migration..."
echo "====================================="
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f /migrations/seed_data.sql

if [ $? -eq 0 ]; then
    echo "Seed data migration completed successfully!"
else
    echo "ERROR: Seed data migration failed"
    exit 1
fi

# Verify tables created
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

# Count tables
TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT COUNT(*)
FROM pg_tables
WHERE schemaname = 'public';
" | tr -d ' ')

echo ""
echo "====================================="
echo "Migration Summary:"
echo "====================================="
echo "Tables created: $TABLE_COUNT"
echo "Expected tables: 10"

if [ "$TABLE_COUNT" -eq 10 ]; then
    echo "✅ All tables created successfully!"
    exit 0
else
    echo "⚠️  Warning: Expected 10 tables but found $TABLE_COUNT"
    exit 1
fi
