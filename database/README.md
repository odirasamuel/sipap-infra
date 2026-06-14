# SIPAP Database Migration System

## Table of Contents
1. [What is Database Migration?](#what-is-database-migration)
2. [Why We Need Database Migrations](#why-we-need-database-migrations)
3. [Migration Architecture](#migration-architecture)
4. [Directory Structure](#directory-structure)
5. [Migration Process](#migration-process)
6. [Files Explained](#files-explained)
7. [How to Run Migrations](#how-to-run-migrations)
8. [Troubleshooting](#troubleshooting)

---

## What is Database Migration?

**Database migration** is the process of moving data, schema, or configuration from one database state to another. In SIPAP's context, migrations are used to:

- **Create initial database schema** (tables, indexes, constraints)
- **Seed reference data** (sports, leagues, markets, bet types)
- **Update schema over time** (add columns, modify constraints, create new tables)
- **Transform data** (data cleanup, format changes, migrations between database engines)

Think of it as "version control for your database structure" - just like Git tracks code changes, migrations track database schema evolution.

---

## Why We Need Database Migrations

### 1. **Fresh RDS Instance Deployment**
After replacing Aurora Serverless v2 with a Standard RDS instance (db.t4g.micro) for cost optimization, we have an **empty PostgreSQL database** that needs:
- Schema creation (10 tables: users, sports, leagues, matches, predictions, etc.)
- Reference data (4 sports, 5 leagues)
- Indexes and constraints

### 2. **Environment Consistency**
Ensure **identical database structure** across:
- Development (`dev`)
- Staging/Test
- Production (`prod`)

### 3. **Reproducibility**
Migrations provide:
- **Auditable history** of schema changes
- **Rollback capability** if issues arise
- **Documentation** of database evolution
- **Team collaboration** - everyone works with the same schema

### 4. **Safe Schema Evolution**
As SIPAP grows, we'll need to:
- Add new tables (e.g., `user_subscriptions`, `payment_history`)
- Modify existing tables (e.g., add `confidence_interval` column to `predictions`)
- Update reference data (e.g., add new sports like Rugby, Tennis)

Migrations make this **safe, predictable, and reversible**.

---

## Migration Architecture

SIPAP uses a **containerized migration system** running on **ECS Fargate** for secure, repeatable deployments.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions Workflow                   │
│  ┌──────────────┐    ┌────────────┐    ┌────────────────┐  │
│  │ Build Docker │ -> │ Push to    │ -> │ Tag with       │  │
│  │ Image (amd64)│    │ Amazon ECR │    │ sha + latest   │  │
│  └──────────────┘    └────────────┘    └────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Amazon ECR (Elastic Container Registry)         │
│  Repository: sipap-migrations                                │
│  Image: 810278669998.dkr.ecr.us-east-1.amazonaws.com/       │
│         sipap-migrations:latest                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ECS Fargate Task                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Migration Container                                  │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │ 1. Retrieve DB password from Secrets Manager│   │   │
│  │  │ 2. Wait for database to be ready (psql)     │   │   │
│  │  │ 3. Run schema.sql (CREATE TABLES)           │   │   │
│  │  │ 4. Run seed_data.sql (INSERT reference data)│   │   │
│  │  │ 5. Verify 10 tables created                 │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Environment Variables (from Terraform)              │   │
│  │  • DB_HOST: RDS endpoint                            │   │
│  │  • DB_NAME: sipap_dev                               │   │
│  │  • DB_USER: sipap_admin                             │   │
│  │  • SECRET_ARN: Password secret ARN                  │   │
│  │  • AWS_REGION: us-east-1                            │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│          RDS PostgreSQL Instance (Private Subnet)            │
│  • Instance: db.t4g.micro                                    │
│  • Engine: PostgreSQL 15.17                                  │
│  • Storage: 20 GB GP3 (autoscaling to 100 GB)               │
│  • Network: Private subnets only (no public access)          │
│  • Security: Accessed only via VPC (ECS tasks in same VPC)   │
└─────────────────────────────────────────────────────────────┘
```

### Key Security Features

1. **Private Network Access**: Migration container runs in same VPC as RDS
2. **No Public Access**: Database is NOT publicly accessible
3. **Secrets Manager**: Password retrieved securely at runtime (never hardcoded)
4. **IAM Authentication**: ECS task role has minimal required permissions
5. **Encrypted Storage**: RDS storage encrypted at rest
6. **Encrypted Transit**: PostgreSQL connections use SSL/TLS

---

## Directory Structure

```
sipap-terraform/database/
├── README.md              # This file - comprehensive migration guide
├── Dockerfile             # Container definition for migration runner
├── run-migration.sh       # Bash script executed inside container
├── schema.sql             # Database schema (CREATE TABLE statements)
├── seed_data.sql          # Reference data (INSERT statements)
└── deploy-and-run-migrations.sh  # Local development helper (deprecated)
```

### Relationship to Other Terraform Files

```
sipap-terraform/
├── migrations.tf          # ECS task definition and ECR repository
├── modules/rds/           # RDS module (creates database instance)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── environments/
│   └── dev.tfvars        # Environment-specific configuration
└── database/             # Migration files (this directory)
    └── ...
```

---

## Migration Process

### Step-by-Step Execution Flow

```
┌────────────────────────────────────────────────────────┐
│ PHASE 1: Build and Push (GitHub Actions)              │
├────────────────────────────────────────────────────────┤
│ 1. Trigger: Push to main branch OR manual workflow    │
│ 2. Build Docker image on amd64 runner (ubuntu-latest) │
│ 3. Tag image: <ecr-url>/sipap-migrations:latest       │
│ 4. Push to Amazon ECR                                  │
│ 5. Update ECS task definition to force new deployment │
└────────────────────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────┐
│ PHASE 2: Run Migration (Manual ECS Task)              │
├────────────────────────────────────────────────────────┤
│ 1. Trigger ECS task via AWS CLI or Console            │
│ 2. ECS pulls latest image from ECR                    │
│ 3. Container starts in private subnet                 │
│ 4. Entrypoint: /bin/bash /run-migration.sh            │
└────────────────────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────┐
│ PHASE 3: Migration Execution (Inside Container)       │
├────────────────────────────────────────────────────────┤
│ Step 1: Retrieve DB password from Secrets Manager     │
│         ├─ Read SECRET_ARN env var                    │
│         ├─ Call: aws secretsmanager get-secret-value  │
│         └─ Export as PGPASSWORD                        │
│                                                        │
│ Step 2: Wait for database readiness                   │
│         ├─ Retry loop: psql -h $DB_HOST -U $DB_USER   │
│         ├─ Test: SELECT 1                             │
│         └─ Exit when connection succeeds               │
│                                                        │
│ Step 3: Run schema migration                          │
│         ├─ Execute: psql -f /migrations/schema.sql    │
│         ├─ Creates: 10 tables, indexes, constraints   │
│         └─ Verify: Exit code 0 (success)              │
│                                                        │
│ Step 4: Run seed data migration                       │
│         ├─ Execute: psql -f /migrations/seed_data.sql │
│         ├─ Inserts: 4 sports, 5 leagues               │
│         └─ Verify: Exit code 0 (success)              │
│                                                        │
│ Step 5: Verification                                  │
│         ├─ Query: SELECT COUNT(*) FROM pg_tables      │
│         ├─ Expected: 10 tables                        │
│         ├─ Actual: {count}                            │
│         └─ Exit: 0 (success) or 1 (failure)           │
└────────────────────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────────┐
│ PHASE 4: Monitoring and Verification                  │
├────────────────────────────────────────────────────────┤
│ 1. View logs: CloudWatch Logs /ecs/sipap-dev-migrations│
│ 2. Check task status: STOPPED with exit code 0        │
│ 3. Verify tables: Connect to RDS and query pg_tables  │
└────────────────────────────────────────────────────────┘
```

### Execution Modes

1. **Automated (CI/CD)**: GitHub Actions builds image → Manual trigger of ECS task
2. **Manual (Developer)**: Trigger ECS task via AWS Console or CLI
3. **One-Time Setup**: Run once to initialize fresh database
4. **Incremental Updates**: Run new migrations as schema evolves

---

## Files Explained

### 1. `Dockerfile`

**Purpose**: Defines the migration container image.

**Base Image**: `postgres:15-alpine` (lightweight PostgreSQL client)

**Installed Tools**:
- `aws-cli`: Retrieve secrets from AWS Secrets Manager
- `jq`: Parse JSON responses from AWS API
- `bash`: Shell for running migration script
- `dos2unix`: Convert line endings (handles CRLF → LF conversion)

**File Operations**:
```dockerfile
COPY schema.sql /migrations/schema.sql         # Database schema
COPY seed_data.sql /migrations/seed_data.sql   # Reference data
COPY run-migration.sh /run-migration.sh        # Migration script
RUN dos2unix /run-migration.sh && chmod +x     # Fix line endings + make executable
```

**Entrypoint**: `/bin/bash /run-migration.sh` (explicitly use bash to avoid exec format errors)

**Why amd64 Build?** ECS Fargate runs on x86_64 architecture. Building on MacBook (ARM64) would create incompatible images. GitHub Actions runner (`ubuntu-latest`) uses amd64.

---

### 2. `run-migration.sh`

**Purpose**: Bash script that orchestrates the migration process inside the container.

**Environment Variables** (injected by ECS task definition):
- `DB_HOST`: RDS endpoint (e.g., `sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com`)
- `DB_PORT`: PostgreSQL port (`5432`)
- `DB_NAME`: Database name (`sipap_dev`)
- `DB_USER`: Database username (`sipap_admin`)
- `SECRET_ARN`: ARN of password secret in Secrets Manager
- `AWS_REGION`: AWS region (`us-east-1`)

**Script Sections**:

1. **Password Retrieval** (Lines 20-37):
   ```bash
   DB_PASSWORD=$(aws secretsmanager get-secret-value \
       --secret-id "$SECRET_ARN" \
       --region "$AWS_REGION" \
       --query 'SecretString' \
       --output text)
   export PGPASSWORD="$DB_PASSWORD"  # PostgreSQL uses this env var
   ```

2. **Database Readiness Check** (Lines 39-47):
   ```bash
   until psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c '\q'; do
       echo "Database is unavailable - sleeping"
       sleep 2
   done
   ```
   **Why?** RDS instance might be starting, network might be initializing. Retry loop prevents race conditions.

3. **Schema Migration** (Lines 49-61):
   ```bash
   psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f /migrations/schema.sql
   ```
   **Creates**: 10 tables, indexes, foreign keys, constraints

4. **Seed Data Migration** (Lines 63-75):
   ```bash
   psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f /migrations/seed_data.sql
   ```
   **Inserts**: Reference data (sports, leagues)

5. **Verification** (Lines 77-111):
   ```bash
   TABLE_COUNT=$(psql ... -t -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';" | tr -d ' ')
   if [ "$TABLE_COUNT" -eq 10 ]; then
       exit 0  # Success
   else
       exit 1  # Failure
   fi
   ```

**Exit Codes**:
- `0`: Success (all migrations applied, 10 tables verified)
- `1`: Failure (migration error or table count mismatch)

---

### 3. `schema.sql`

**Purpose**: Database schema definition (DDL - Data Definition Language).

**Contents**:
- `CREATE TABLE` statements for 10 tables
- Primary keys, foreign keys, constraints
- Indexes for query optimization
- JSONB columns for structured data (e.g., `metadata JSONB`)

**Tables Created**:
1. `users` - User accounts and profiles
2. `sports` - Supported sports (Soccer, Basketball, etc.)
3. `leagues` - Sports leagues (Premier League, NBA, etc.)
4. `teams` - Sports teams
5. `matches` - Scheduled matches
6. `odds` - Betting odds from providers
7. `predictions` - AI-generated predictions
8. `intelligence_sources` - Data source tracking
9. `user_subscriptions` - User notification preferences
10. `audit_log` - System activity tracking

**Example**:
```sql
CREATE TABLE IF NOT EXISTS sports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(150) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sports_name ON sports(name);
```

**Idempotency**: Uses `IF NOT EXISTS` - safe to run multiple times without errors.

---

### 4. `seed_data.sql`

**Purpose**: Initial reference data (DML - Data Manipulation Language).

**Contents**:
- `INSERT` statements for core reference data
- Uses `ON CONFLICT DO NOTHING` for idempotency

**Data Inserted**:

**Sports** (4 records):
```sql
INSERT INTO sports (name, display_name, metadata) VALUES
    ('soccer', 'Soccer', '{"aliases": ["football"], "popularity": "high"}'),
    ('basketball', 'Basketball', '{"popularity": "high"}'),
    ('american_football', 'American Football', '{"aliases": ["nfl"], "popularity": "high"}'),
    ('tennis', 'Tennis', '{"popularity": "medium"}')
ON CONFLICT (name) DO NOTHING;
```

**Leagues** (5 records):
```sql
INSERT INTO leagues (sport_id, name, display_name, country, metadata) VALUES
    ((SELECT id FROM sports WHERE name = 'soccer'), 'premier_league', 'Premier League', 'England', '{"tier": 1}'),
    ((SELECT id FROM sports WHERE name = 'basketball'), 'nba', 'NBA', 'USA', '{"tier": 1}'),
    ...
ON CONFLICT (name) DO NOTHING;
```

**Why Seed Data?** These are **foundational entities** that the application expects to exist. Without them, the app cannot:
- Classify incoming matches
- Display sport/league names to users
- Filter predictions by sport

**Idempotency**: Uses `ON CONFLICT (name) DO NOTHING` - safe to run multiple times.

---

### 5. `deploy-and-run-migrations.sh`

**Purpose**: **DEPRECATED** - Local development helper script.

**Why Deprecated?** Building Docker images on MacBook (ARM64) creates architecture mismatches with ECS Fargate (amd64). This script is kept for reference but **should NOT be used**.

**Replacement**: Use GitHub Actions workflow (builds on amd64 runner).

**Contents**:
- Terraform apply
- Docker build + push to ECR
- ECS task execution
- Log monitoring

**Status**: ⚠️ **DO NOT USE** - Use GitHub Actions instead.

---

### 6. `migrations.tf` (Parent Directory)

**Purpose**: Terraform configuration for migration infrastructure.

**Resources Created**:

1. **ECR Repository** (`aws_ecr_repository.migrations`):
   ```hcl
   resource "aws_ecr_repository" "migrations" {
     name                 = "sipap-migrations"
     image_tag_mutability = "MUTABLE"
     encryption_configuration {
       encryption_type = "AES256"
     }
   }
   ```
   **Output**: `migrations_repository_url` (e.g., `810278669998.dkr.ecr.us-east-1.amazonaws.com/sipap-migrations`)

2. **ECS Task Definition** (`aws_ecs_task_definition.migrations`):
   ```hcl
   resource "aws_ecs_task_definition" "migrations" {
     family                   = "sipap-dev-migrations"
     network_mode             = "awsvpc"
     requires_compatibilities = ["FARGATE"]
     cpu                      = "256"   # 0.25 vCPU
     memory                   = "512"   # 512 MB
     execution_role_arn       = module.ecs_task_execution_role.role_arn

     container_definitions = jsonencode([{
       name  = "migrations"
       image = "${aws_ecr_repository.migrations.repository_url}:latest"
       environment = [
         {name = "DB_HOST", value = module.aurora.endpoint},
         {name = "DB_NAME", value = var.database_name},
         ...
       ]
     }])
   }
   ```
   **Output**: `migrations_task_definition` (ARN used to run ECS task)

3. **CloudWatch Log Group** (`aws_cloudwatch_log_group.migrations`):
   ```hcl
   resource "aws_cloudwatch_log_group" "migrations" {
     name              = "/ecs/sipap-dev-migrations"
     retention_in_days = 7
   }
   ```
   **Purpose**: Store migration logs for debugging and audit trails.

---

## How to Run Migrations

### Prerequisites

1. **Infrastructure Deployed**: Terraform apply completed successfully
2. **RDS Instance Running**: Database available in private subnet
3. **ECR Repository Created**: `sipap-migrations` repository exists
4. **GitHub Actions Workflow**: Migration image built and pushed to ECR

---

### Method 1: GitHub Actions + Manual ECS Task (Recommended)

**Step 1: Trigger GitHub Actions Workflow**

```bash
# Option A: Push to main branch (auto-trigger)
git add database/
git commit -m "Update database migrations"
git push origin main

# Option B: Manual workflow dispatch
# Go to: https://github.com/<org>/<repo>/actions
# Select "Build and Push Database Migration Image"
# Click "Run workflow"
```

**Step 2: Verify Image in ECR**

```bash
aws ecr describe-images \
    --repository-name sipap-migrations \
    --region us-east-1 \
    --profile odiraaws \
    --query 'imageDetails[0].{digest:imageDigest,tags:imageTags,pushedAt:imagePushedAt}'
```

**Step 3: Run ECS Migration Task**

```bash
# Get Terraform outputs
cd sipap-terraform/
TASK_DEF=$(terraform output -raw migrations_task_definition)
PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r 'join(",")')
DB_SG=$(terraform output -raw ecs_tasks_sg_id)

# Run ECS task
aws ecs run-task \
    --cluster sipap-dev-cluster \
    --task-definition $TASK_DEF \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$DB_SG],assignPublicIp=DISABLED}" \
    --region us-east-1 \
    --profile odiraaws
```

**Step 4: Monitor Logs**

```bash
# Stream logs (real-time)
aws logs tail /ecs/sipap-dev-migrations \
    --follow \
    --format short \
    --region us-east-1 \
    --profile odiraaws

# Or view in AWS Console:
# CloudWatch → Log groups → /ecs/sipap-dev-migrations
```

**Step 5: Verify Success**

```bash
# Check task status
aws ecs describe-tasks \
    --cluster sipap-dev-cluster \
    --tasks <TASK_ARN> \
    --region us-east-1 \
    --profile odiraaws \
    --query 'tasks[0].{status:lastStatus,exitCode:containers[0].exitCode}'

# Expected output:
# {
#     "status": "STOPPED",
#     "exitCode": 0
# }
```

---

### Method 2: AWS Console (Manual)

1. **Navigate to ECS Console**: https://console.aws.amazon.com/ecs/
2. **Select Cluster**: `sipap-dev-cluster`
3. **Task Definitions**: Find `sipap-dev-migrations:latest`
4. **Run Task**:
   - Launch type: `FARGATE`
   - Cluster: `sipap-dev-cluster`
   - VPC: Select SIPAP VPC
   - Subnets: Select **private subnets**
   - Security group: `ecs_tasks_sg`
   - Auto-assign public IP: `DISABLED`
5. **Monitor**: View task in "Tasks" tab, click task ID → "Logs" tab
6. **Verify**: Check exit code (0 = success)

---

## Troubleshooting

### Issue 1: Container Fails with "exec format error"

**Symptom**: ECS task stops immediately with exit code 255, logs show:
```
exec /run-migration.sh: exec format error
```

**Root Cause**: Docker image built on ARM64 (MacBook) incompatible with ECS Fargate (amd64).

**Solution**: Use GitHub Actions workflow to build on `ubuntu-latest` (amd64) runner.

---

### Issue 2: Database Connection Timeout

**Symptom**: Logs show:
```
Database is unavailable - sleeping
Database is unavailable - sleeping
...
```

**Root Cause**: Security group or network configuration blocking access.

**Solution**:
1. Verify ECS task in same VPC as RDS
2. Check security group allows inbound on port 5432 from ECS tasks SG
3. Verify RDS is in private subnets
4. Check VPC route tables

---

### Issue 3: Secrets Manager Permission Denied

**Symptom**: Logs show:
```
ERROR: Failed to retrieve database password
An error occurred (AccessDeniedException) when calling GetSecretValue
```

**Root Cause**: ECS task execution role missing Secrets Manager permissions.

**Solution**: Verify IAM role `sipap-dev-ecs-task-execution-role` has policy:
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue"
  ],
  "Resource": "arn:aws:secretsmanager:*:*:secret:sipap-*"
}
```

---

### Issue 4: Table Count Mismatch

**Symptom**: Logs show:
```
⚠️  Warning: Expected 10 tables but found 8
```

**Root Cause**: `schema.sql` has errors or was partially executed.

**Solution**:
1. Check CloudWatch logs for SQL errors
2. Connect to RDS manually:
   ```bash
   psql -h <rds-endpoint> -U sipap_admin -d sipap_dev
   \dt  # List tables
   ```
3. Fix `schema.sql` and re-run migration

---

### Issue 5: Migration Already Run (Idempotency)

**Symptom**: Want to re-run migration but tables already exist.

**Root Cause**: Migrations are idempotent but may skip existing tables.

**Solution**:
- **Safe**: Migrations use `IF NOT EXISTS` and `ON CONFLICT DO NOTHING` - safe to re-run
- **Clean slate**: Drop all tables first:
  ```sql
  DROP SCHEMA public CASCADE;
  CREATE SCHEMA public;
  ```

---

## Future Enhancements

### 1. Alembic Integration (Planned)

**Goal**: Use **Alembic** (Python database migration tool) for versioned schema evolution.

**Benefits**:
- **Version control**: Each migration has a unique version number
- **Upgrade/downgrade**: Rollback capability
- **Auto-generation**: Generate migrations from SQLAlchemy models
- **Migration history**: Track which migrations have been applied

**Implementation** (Future):
```
database/
├── alembic/
│   ├── versions/
│   │   ├── 001_initial_schema.py
│   │   ├── 002_add_confidence_interval.py
│   │   └── 003_add_user_subscriptions.py
│   └── env.py
├── alembic.ini
└── run-alembic.sh
```

### 2. Automated Migration Triggers

**Goal**: Trigger migrations automatically on infrastructure deployment.

**Options**:
- **Terraform `local-exec` provisioner**: Run migration after RDS creation
- **AWS Lambda**: Trigger migration via CloudFormation custom resource
- **GitHub Actions**: Integrated deployment pipeline (infra → migrate → deploy app)

### 3. Blue/Green Migration Strategy

**Goal**: Zero-downtime migrations for production.

**Approach**:
- Run new schema migrations on a copy of the database
- Test application with new schema
- Switchover traffic to new database
- Keep old database as rollback option

---

## Best Practices

1. **Always Test Migrations**:
   - Run in development first
   - Verify table counts and data integrity
   - Check application functionality

2. **Backup Before Migration**:
   - Take RDS snapshot before production migrations
   - Keep backup for 7-30 days

3. **Monitor Migration Logs**:
   - Check CloudWatch logs for errors
   - Verify exit code = 0

4. **Version Control**:
   - Commit all migration files to Git
   - Tag releases with migration version

5. **Document Changes**:
   - Update CHANGELOG.md with schema changes
   - Add comments to complex SQL

---

## Support

For questions or issues:
- **Slack**: #sipap-dev channel
- **Documentation**: `sipap/IMPLEMENTATION-ROADMAP.md`
- **AWS Console**: CloudWatch Logs → `/ecs/sipap-dev-migrations`
