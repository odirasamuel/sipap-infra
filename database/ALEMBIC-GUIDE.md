# Alembic Migration Guide for SIPAP

**Version-Controlled Database Schema Evolution**

## Table of Contents
1. [What is Alembic?](#what-is-alembic)
2. [Why We Use Alembic](#why-we-use-alembic)
3. [Migration Workflow](#migration-workflow)
4. [Creating New Migrations](#creating-new-migrations)
5. [Applying Migrations](#applying-migrations)
6. [Rolling Back Migrations](#rolling-back-migrations)
7. [Migration History](#migration-history)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

---

## What is Alembic?

**Alembic is Git for your database schema.**

Just like Git tracks code changes over time with commits, Alembic tracks **database schema changes** over time with **migration files**.

### Core Concepts

**1. Migrations = Versioned Schema Changes**
Each schema change is a numbered Python file:
```
alembic/versions/
├── 20260614_001_initial_schema.py          # Baseline: 10 tables
├── 20260620_002_add_email_verified.py      # Future: Add column
├── 20260625_003_create_agent_metrics.py    # Future: New table
```

**2. Upgrade = Move Forward**
```python
def upgrade():
    op.add_column('users', sa.Column('email_verified', sa.Boolean()))
```

**3. Downgrade = Move Backward (Rollback)**
```python
def downgrade():
    op.drop_column('users', 'email_verified')
```

**4. Version Tracking**
Alembic creates a special table `alembic_version` to track which migration is currently applied:
```sql
SELECT * FROM alembic_version;
-- Returns: 20260614_001  (current version)
```

---

## Why We Use Alembic

### Problem: Manual SQL Schema Changes

**Without Alembic:**
```bash
# Developer writes SQL manually
psql -c "ALTER TABLE users ADD COLUMN email_verified BOOLEAN;"

# Problems:
# ❌ Did this run in dev? staging? prod?
# ❌ What if it fails halfway through?
# ❌ How do we rollback?
# ❌ No version control — what changed when?
```

### Solution: Automated Version-Controlled Migrations

**With Alembic:**
```bash
# Step 1: Create migration
alembic revision -m "add email_verified to users"

# Step 2: Edit generated file
# alembic/versions/002_add_email_verified.py
def upgrade():
    op.add_column('users', sa.Column('email_verified', sa.Boolean()))

def downgrade():
    op.drop_column('users', 'email_verified')

# Step 3: Apply migration
alembic upgrade head

# Step 4: If something breaks
alembic downgrade -1  # Rollback last migration
```

**Benefits:**
- ✅ Version controlled (in Git)
- ✅ Auditable (who changed what when)
- ✅ Rollback capability (downgrade function)
- ✅ Multi-environment (same migration runs everywhere)
- ✅ Automated via GitHub Actions

---

## Migration Workflow

### Current Setup (Automated via GitHub Actions)

```
Push to database/ → GitHub Actions Workflow
                         ↓
                   Build Docker Image (with Alembic)
                         ↓
                   Push to ECR
                         ↓
                   Run ECS Fargate Task
                         ↓
                   Execute: alembic upgrade head
                         ↓
                   Verify: 10 tables exist
```

**Result:** Zero manual steps. Migrations run automatically on every push.

---

## Creating New Migrations

### Scenario: Add `email_verified` Column to Users Table

**Step 1: Create Migration File**
```bash
# Inside the database/ directory
alembic revision -m "add email_verified to users"
```

This generates:
```
alembic/versions/20260620_1430_add_email_verified_to_users.py
```

**Step 2: Edit Migration File**
```python
"""add email_verified to users

Revision ID: 20260620_1430
Revises: 20260614_001
Create Date: 2026-06-20 14:30:00
"""
from alembic import op
import sqlalchemy as sa

revision = '20260620_1430'
down_revision = '20260614_001'  # Previous migration
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add email_verified column to users table"""
    op.add_column(
        'users',
        sa.Column('email_verified', sa.Boolean(), nullable=True, server_default='false')
    )
    # Create index for faster lookups
    op.create_index('idx_users_email_verified', 'users', ['email_verified'])


def downgrade() -> None:
    """Remove email_verified column from users table"""
    op.drop_index('idx_users_email_verified', table_name='users')
    op.drop_column('users', 'email_verified')
```

**Step 3: Test Migration Locally (Optional)**
```bash
# Connect to dev database via port forwarding or bastion
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=sipap_dev
export DB_USER=sipap_admin
export DB_PASSWORD=your_password

# Apply migration
alembic upgrade head

# Verify
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\d users"
# Should show email_verified column

# Rollback (if testing)
alembic downgrade -1

# Re-apply
alembic upgrade head
```

**Step 4: Commit and Push**
```bash
git add database/alembic/versions/20260620_1430_add_email_verified_to_users.py
git commit -m "Add email_verified column to users table"
git push origin main
```

**Step 5: Automated Deployment**
GitHub Actions workflow will:
1. Build new Docker image with your migration
2. Push to ECR
3. Run ECS task
4. Execute `alembic upgrade head`
5. Apply your new migration automatically

---

## Applying Migrations

### Manual Application (Bastion/Local)

**Apply All Pending Migrations:**
```bash
alembic upgrade head
```

**Apply Specific Migration:**
```bash
alembic upgrade 20260620_1430
```

**Apply Next Migration Only:**
```bash
alembic upgrade +1
```

### Automated Application (Production)

**Via GitHub Actions (Recommended):**
```bash
# Push to database/ directory triggers workflow
git add database/
git commit -m "Add new migration"
git push origin main
```

**Via Manual Workflow Dispatch:**
1. Go to GitHub Actions
2. Select "Build and Push Database Migration Image"
3. Click "Run workflow"

---

## Rolling Back Migrations

### Manual Rollback (Bastion/Local)

**Rollback Last Migration:**
```bash
alembic downgrade -1
```

**Rollback to Specific Version:**
```bash
alembic downgrade 20260614_001
```

**Rollback All Migrations:**
```bash
alembic downgrade base
```

### Emergency Production Rollback

**Scenario:** Deployment failed, need to rollback immediately.

**Option 1: Rollback via Bastion/Port Forwarding**
```bash
# Connect to database
export DB_HOST=sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com
export DB_PORT=5432
export DB_NAME=sipap_dev
export DB_USER=sipap_admin
export DB_PASSWORD=$(aws secretsmanager get-secret-value ...)

# Rollback
alembic downgrade -1
```

**Option 2: Rollback via ECS Task**
```bash
# Run migration container with downgrade command
# (Requires updating run-migration.sh to support MIGRATION_COMMAND env var)
export MIGRATION_COMMAND="alembic downgrade -1"
# Then run ECS task
```

---

## Migration History

### View Migration History

**Show All Migrations:**
```bash
alembic history
```

Output:
```
20260620_1430 -> 20260625_1500 (head), create agent_metrics table
20260614_001 -> 20260620_1430, add email_verified to users
<base> -> 20260614_001, initial schema and seed data
```

**Show Current Version:**
```bash
alembic current
```

Output:
```
20260625_1500 (head)
```

**Show Pending Migrations:**
```bash
# If current = 20260614_001 and head = 20260625_1500
alembic history --verbose

# Output shows pending migrations
```

---

## Best Practices

### 1. Always Write Downgrade Functions

**Bad:**
```python
def downgrade() -> None:
    pass  # ❌ No rollback capability
```

**Good:**
```python
def upgrade() -> None:
    op.add_column('users', sa.Column('email_verified', sa.Boolean()))

def downgrade() -> None:
    op.drop_column('users', 'email_verified')  # ✅ Can rollback
```

### 2. Test Migrations Locally First

**Workflow:**
```bash
# Step 1: Apply migration locally
alembic upgrade head

# Step 2: Verify schema
psql -c "\d users"

# Step 3: Rollback
alembic downgrade -1

# Step 4: Re-apply
alembic upgrade head

# Step 5: If both work, push to production
```

### 3. Use Descriptive Migration Messages

**Bad:**
```bash
alembic revision -m "update"  # ❌ What update?
```

**Good:**
```bash
alembic revision -m "add confidence_score to predictions"  # ✅ Clear intent
```

### 4. One Logical Change Per Migration

**Bad:**
```python
def upgrade():
    # ❌ Too many unrelated changes
    op.add_column('users', ...)
    op.create_table('agent_metrics', ...)
    op.drop_column('predictions', ...)
```

**Good:**
```python
# Migration 002: Add email_verified to users
def upgrade():
    op.add_column('users', ...)

# Migration 003: Create agent_metrics table
def upgrade():
    op.create_table('agent_metrics', ...)

# Migration 004: Remove old prediction column
def upgrade():
    op.drop_column('predictions', ...)
```

### 5. Never Edit Applied Migrations

**Rule:** Once a migration is applied to production, **never edit it**.

**Why?** Alembic tracks migrations by file hash. Changing a migration breaks the version chain.

**If you need to fix a migration:**
```bash
# ❌ Don't edit 002_add_email_verified.py
# ✅ Create new migration: 003_fix_email_verified.py
alembic revision -m "fix email_verified default value"
```

### 6. Handle Data Migrations Carefully

**Example: Populating New Column**
```python
def upgrade():
    # Step 1: Add column (nullable)
    op.add_column('users', sa.Column('email_verified', sa.Boolean(), nullable=True))

    # Step 2: Populate existing rows
    op.execute("UPDATE users SET email_verified = false WHERE email_verified IS NULL")

    # Step 3: Make column NOT NULL
    op.alter_column('users', 'email_verified', nullable=False)
```

### 7. Backup Before Major Migrations

**Before applying migrations to production:**
```bash
# Create RDS snapshot
aws rds create-db-snapshot \
    --db-instance-identifier sipap-dev-rds \
    --db-snapshot-identifier sipap-pre-migration-$(date +%Y%m%d)
```

---

## Troubleshooting

### Problem: Migration Fails Halfway

**Symptom:**
```
ERROR: column "email_verified" already exists
```

**Cause:** Migration partially applied, then failed.

**Solution:**
```bash
# Option 1: Manually fix database state
psql -c "ALTER TABLE users DROP COLUMN email_verified;"

# Option 2: Mark migration as applied (if schema is correct)
alembic stamp head

# Option 3: Rollback and re-apply
alembic downgrade -1
alembic upgrade head
```

### Problem: alembic_version Out of Sync

**Symptom:**
```
ERROR: Can't locate revision identified by '20260620_1430'
```

**Cause:** Migration file deleted or git branch mismatch.

**Solution:**
```bash
# Check what version database thinks it's on
psql -c "SELECT * FROM alembic_version;"

# Manually set to correct version
alembic stamp 20260614_001  # Reset to known good state

# Re-apply migrations
alembic upgrade head
```

### Problem: Downgrade Fails

**Symptom:**
```
ERROR: cannot drop column email_verified because other objects depend on it
```

**Cause:** Downgrade function didn't account for dependencies (indexes, constraints).

**Solution:**
```python
def downgrade():
    # ✅ Drop dependencies first
    op.drop_index('idx_users_email_verified', table_name='users')
    op.drop_column('users', 'email_verified')
```

---

## Common Migration Patterns

### 1. Add Column
```python
def upgrade():
    op.add_column('users', sa.Column('email_verified', sa.Boolean(), server_default='false'))

def downgrade():
    op.drop_column('users', 'email_verified')
```

### 2. Create Table
```python
def upgrade():
    op.create_table(
        'agent_metrics',
        sa.Column('id', sa.UUID(), primary_key=True),
        sa.Column('agent_name', sa.String(100), nullable=False),
        sa.Column('response_time_ms', sa.Integer()),
        sa.Column('created_at', sa.TIMESTAMP(), server_default=sa.text('CURRENT_TIMESTAMP'))
    )

def downgrade():
    op.drop_table('agent_metrics')
```

### 3. Add Index
```python
def upgrade():
    op.create_index('idx_predictions_match_id', 'predictions', ['match_id'])

def downgrade():
    op.drop_index('idx_predictions_match_id', table_name='predictions')
```

### 4. Modify Column Type
```python
def upgrade():
    # Change phone_number from VARCHAR(20) to VARCHAR(30)
    op.alter_column('users', 'phone_number', type_=sa.String(30))

def downgrade():
    op.alter_column('users', 'phone_number', type_=sa.String(20))
```

### 5. Rename Column
```python
def upgrade():
    op.alter_column('users', 'whatsapp_id', new_column_name='whatsapp_number')

def downgrade():
    op.alter_column('users', 'whatsapp_number', new_column_name='whatsapp_id')
```

### 6. Execute Raw SQL
```python
def upgrade():
    op.execute("""
        CREATE OR REPLACE FUNCTION update_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)

def downgrade():
    op.execute("DROP FUNCTION IF EXISTS update_updated_at();")
```

---

## Integration with GitHub Actions

### Current Workflow

**File:** `.github/workflows/build-migration-image.yml`

**Job 1: Build & Push**
- Builds Docker image with Alembic and migration files
- Pushes to ECR

**Job 2: Run Migration**
- Runs ECS task
- Executes `alembic upgrade head` inside container
- Verifies migration success

**Trigger:**
```bash
# Option A: Push to database/ directory
git add database/alembic/versions/002_new_migration.py
git commit -m "Add new migration"
git push origin main

# Option B: Manual workflow dispatch
# Go to GitHub Actions → Run workflow
```

---

## Summary

**Alembic gives us:**
- ✅ Version-controlled schema evolution
- ✅ Automated deployments via GitHub Actions
- ✅ Rollback capability if deployments fail
- ✅ Clear migration history for auditing
- ✅ Multi-environment consistency (dev, staging, prod)

**Key Commands:**
```bash
# Create migration
alembic revision -m "description"

# Apply migrations
alembic upgrade head

# Rollback
alembic downgrade -1

# View history
alembic history

# Check current version
alembic current
```

**Best Practices:**
1. Always write downgrade functions
2. Test locally before production
3. One logical change per migration
4. Never edit applied migrations
5. Backup before major migrations

---

**Questions?** Check `database/README.md` or CloudWatch logs at `/ecs/sipap-dev-migrations`.
