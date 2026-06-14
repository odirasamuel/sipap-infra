# Database Migration Setup - Summary

**Date**: 2026-06-14
**Status**: ✅ Documentation and CI/CD Pipeline Configured
**Next Steps**: Configure GitHub Actions secrets and test workflow

---

## What We Accomplished

### 1. Comprehensive Documentation ✅

**Created**: `database/README.md` (500+ lines)

**Covers**:
- ✅ What database migration is and why we need it
- ✅ Migration architecture (diagrams + flow charts)
- ✅ Complete directory structure explanation
- ✅ Detailed file-by-file breakdown
- ✅ Step-by-step migration process
- ✅ Troubleshooting guide
- ✅ Security best practices
- ✅ Future enhancements (Alembic integration)

**Key Insights**:
- Explained why we replaced Aurora Serverless v2 with Standard RDS (cost optimization: $43-87/mo → $12/mo)
- Documented the fresh database state (empty → needs schema + seed data)
- Clarified the containerized migration approach (ECS Fargate for secure VPC access)

---

### 2. GitHub Actions CI/CD Pipeline ✅

**Created**: `.github/workflows/build-migration-image.yml`

**Why GitHub Actions?** You correctly identified that building Docker images on MacBook (ARM64/M1) creates architecture mismatches with ECS Fargate (amd64/x86_64). GitHub Actions runners use `ubuntu-latest` (amd64), ensuring compatibility.

**Workflow Features**:
- ✅ **Automatic trigger**: Pushes to `main` branch when `database/` files change
- ✅ **Manual trigger**: Workflow dispatch for on-demand builds
- ✅ **OIDC authentication**: Secure AWS authentication (no access keys in GitHub secrets)
- ✅ **Multi-platform build**: Explicitly builds for `linux/amd64` using Docker Buildx
- ✅ **ECR push**: Pushes image to `sipap-migrations` repository
- ✅ **ECS task definition update**: Forces new task definition revision (ensures ECS pulls new image)
- ✅ **Build summary**: GitHub Actions summary with next steps for running migration

**Workflow Steps**:
1. Checkout repository
2. Configure AWS credentials (OIDC)
3. Login to Amazon ECR
4. Build Docker image (`linux/amd64`)
5. Push to ECR (`sipap-migrations:latest`)
6. Get image digest (SHA256)
7. Update ECS task definition (force new revision)
8. Generate build summary

---

### 3. GitHub Actions Setup Guide ✅

**Created**: `.github/SETUP.md`

**Covers**:
- ✅ IAM role creation for GitHub Actions OIDC
- ✅ Trust policy configuration
- ✅ ECR permissions policy
- ✅ GitHub secrets setup (`AWS_ROLE_ARN`)
- ✅ Workflow testing instructions
- ✅ Troubleshooting common issues
- ✅ Security best practices
- ✅ Monitoring and alerts setup

---

## Migration Infrastructure Status

### ✅ Deployed (via Terraform)

| Resource | Status | Details |
|----------|--------|---------|
| **ECR Repository** | ✅ Created | `sipap-migrations` (810278669998.dkr.ecr.us-east-1.amazonaws.com/sipap-migrations) |
| **ECS Task Definition** | ✅ Created | `sipap-dev-migrations:2` (revision 2) |
| **CloudWatch Log Group** | ✅ Created | `/ecs/sipap-dev-migrations` (7-day retention) |
| **RDS Instance** | ✅ Running | `sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com` (PostgreSQL 15.17, db.t4g.micro) |
| **Security Groups** | ✅ Configured | ECS tasks SG has access to RDS on port 5432 |
| **VPC Configuration** | ✅ Configured | Private subnets, no public IP assignment |

### ⏳ Pending (Next Steps)

| Task | Status | Blocker |
|------|--------|---------|
| **Docker Image in ECR** | ⏳ Pending | GitHub Actions secrets not configured |
| **Database Schema** | ⏳ Pending | Migration not run (empty database) |
| **Reference Data** | ⏳ Pending | Migration not run (no seed data) |

---

## Why We Changed Approach

### Original Approach (Local Docker Build) ❌

**What we tried**:
```bash
# Build on MacBook
docker build -t sipap-migrations:latest .
docker push 810278669998.dkr.ecr.us-east-1.amazonaws.com/sipap-migrations:latest

# Run on ECS
aws ecs run-task --cluster sipap-dev-cluster --task-definition sipap-dev-migrations:2 ...
```

**Problem**:
```
exec /run-migration.sh: exec format error
```

**Root Cause**: MacBook M1/M2 uses ARM64 architecture. ECS Fargate uses amd64/x86_64. Docker image built on ARM64 is incompatible with ECS.

**Attempted Fixes**:
- ❌ dos2unix (fixed line endings)
- ❌ Explicit bash entrypoint (`/bin/bash /run-migration.sh`)
- ❌ Force new task definition revision

**Result**: Architecture mismatch cannot be fixed without building on amd64 platform.

---

### New Approach (GitHub Actions) ✅

**What we're doing**:
```yaml
# GitHub Actions runner (ubuntu-latest = amd64)
docker buildx build --platform linux/amd64 -t sipap-migrations:latest .
docker push 810278669998.dkr.ecr.us-east-1.amazonaws.com/sipap-migrations:latest
```

**Benefits**:
- ✅ Guaranteed amd64 architecture (compatible with ECS Fargate)
- ✅ Automated builds on code changes
- ✅ Secure OIDC authentication (no AWS access keys)
- ✅ Build history and logs in GitHub Actions
- ✅ Consistent build environment (no "works on my machine" issues)
- ✅ Follows Sentinel's proven pattern

**Sentinel Reference**: Examined `/Users/charlesotuya/AI-Odi/sentinel/repos/sentinel-master/.github/workflows/deploy-orchestrator-deltekdev.yml` for best practices.

---

## File Structure Explained

```
sipap-terraform/
├── .github/
│   ├── workflows/
│   │   └── build-migration-image.yml    # CI/CD pipeline (NEW)
│   └── SETUP.md                          # Setup instructions (NEW)
│
├── database/
│   ├── README.md                         # Comprehensive guide (NEW)
│   ├── MIGRATION-SUMMARY.md              # This file (NEW)
│   ├── Dockerfile                        # Container definition (UPDATED: dos2unix + bash entrypoint)
│   ├── run-migration.sh                  # Migration script (EXISTING)
│   ├── schema.sql                        # Database schema (EXISTING)
│   ├── seed_data.sql                     # Reference data (EXISTING)
│   └── deploy-and-run-migrations.sh      # DEPRECATED: Local build script (DO NOT USE)
│
├── migrations.tf                         # Terraform: ECR + ECS task definition (DEPLOYED)
├── modules/rds/                          # RDS module (DEPLOYED)
└── environments/dev.tfvars               # Environment config (DEPLOYED)
```

### File Purposes

| File | Purpose | Status |
|------|---------|--------|
| `README.md` | **Master documentation**: What, why, how of migrations | ✅ Complete |
| `MIGRATION-SUMMARY.md` | **Executive summary**: What we did, next steps | ✅ This file |
| `.github/workflows/build-migration-image.yml` | **CI/CD pipeline**: Build & push Docker image | ✅ Ready to test |
| `.github/SETUP.md` | **Setup guide**: Configure GitHub secrets | ✅ Complete |
| `Dockerfile` | **Container definition**: Migration runner image | ✅ Updated |
| `run-migration.sh` | **Migration script**: Runs inside container | ✅ Ready |
| `schema.sql` | **Database schema**: 10 tables, indexes, constraints | ✅ Ready |
| `seed_data.sql` | **Reference data**: 4 sports, 5 leagues | ✅ Ready |
| `deploy-and-run-migrations.sh` | **DEPRECATED**: Local build (ARM64 issue) | ❌ DO NOT USE |

---

## Architecture Alignment with Sentinel

### Sentinel's Approach

Examined `sentinel-terraform-master/sentinel_gce/env_vars/deltekdev.tfvars`:

```hcl
ecs_services = [
  {
    name           = "orchestrator-service"
    image          = "343866166964.dkr.ecr.us-east-1.amazonaws.com/sentinel/orchestrator:latest"
    cpu            = 256
    memory         = 512
    desired_count  = 2
    ...
  }
]
```

**Key Insights**:
- ✅ Sentinel uses ECR for all container images
- ✅ GitHub Actions builds and pushes images (`.github/workflows/deploy-orchestrator-deltekdev.yml`)
- ✅ ECS services run from ECR (not local builds)
- ✅ Terraform manages infrastructure, GitHub Actions manages images

### SIPAP's Approach (Aligned)

```hcl
# migrations.tf
resource "aws_ecs_task_definition" "migrations" {
  family = "sipap-dev-migrations"
  cpu    = "256"
  memory = "512"

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

**Alignment**:
- ✅ ECR repository for migration image
- ✅ GitHub Actions builds and pushes image
- ✅ ECS task definition references ECR image
- ✅ Terraform manages infrastructure
- ✅ Manual ECS task execution (one-time setup vs. long-running service)

**Difference**: Sentinel runs services (desired_count = 2), SIPAP runs one-off tasks (desired_count = 0, manual execution).

---

## Next Steps (In Order)

### 1. Configure GitHub Actions Secrets ⏳

**Action Required**: Set up `AWS_ROLE_ARN` secret in GitHub repository.

**Instructions**: Follow `.github/SETUP.md` to:
1. Create IAM OIDC provider (one-time)
2. Create IAM role for GitHub Actions
3. Attach ECR permissions policy
4. Add `AWS_ROLE_ARN` secret to GitHub

**Time Estimate**: 15 minutes

---

### 2. Test GitHub Actions Workflow ⏳

**Action Required**: Trigger workflow to build and push migration image.

**Options**:

**Option A - Automatic Trigger**:
```bash
cd sipap-terraform/database
echo "# Trigger workflow" >> README.md
git add README.md
git commit -m "Trigger migration image build"
git push origin main
```

**Option B - Manual Trigger**:
1. Go to GitHub Actions tab
2. Select "Build & Push Database Migration Image"
3. Click "Run workflow"
4. Monitor progress

**Expected Result**:
- ✅ Image built on amd64
- ✅ Image pushed to ECR (`sipap-migrations:latest`)
- ✅ ECS task definition updated (new revision)
- ✅ GitHub Actions summary generated

**Time Estimate**: 5-10 minutes (build + push)

---

### 3. Run Database Migration ⏳

**Action Required**: Execute ECS task to apply schema and seed data.

**Commands**:
```bash
cd sipap-terraform/

# Get Terraform outputs
TASK_DEF=$(terraform output -raw migrations_task_definition)
PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r 'join(",")')
DB_SG=$(terraform output -raw ecs_tasks_sg_id)

# Run ECS migration task
aws ecs run-task \
    --cluster sipap-dev-cluster \
    --task-definition $TASK_DEF \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$DB_SG],assignPublicIp=DISABLED}" \
    --region us-east-1 \
    --profile odiraaws

# Monitor logs
aws logs tail /ecs/sipap-dev-migrations \
    --follow \
    --format short \
    --region us-east-1 \
    --profile odiraaws
```

**Expected Result**:
```
=====================================
SIPAP Database Migration Script
=====================================
Database Host: sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com
Database Name: sipap_dev
Database User: sipap_admin

Password retrieved successfully
Database is ready!

=====================================
Running schema.sql migration...
=====================================
Schema migration completed successfully!

=====================================
Running seed_data.sql migration...
=====================================
Seed data migration completed successfully!

=====================================
Migration Summary:
=====================================
Tables created: 10
Expected tables: 10
✅ All tables created successfully!
```

**Verification**:
```bash
# Check task exit code (should be 0)
aws ecs describe-tasks \
    --cluster sipap-dev-cluster \
    --tasks <TASK_ARN> \
    --query 'tasks[0].containers[0].exitCode'
```

**Time Estimate**: 2-5 minutes

---

### 4. Verify Database Schema ⏳

**Action Required**: Connect to RDS and verify tables created.

**Option A - psql (from EC2 bastion or local with VPN)**:
```bash
psql -h sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com \
     -U sipap_admin \
     -d sipap_dev

\dt  -- List tables (should show 10 tables)
SELECT * FROM sports;  -- Should show 4 sports
SELECT * FROM leagues;  -- Should show 5 leagues
```

**Option B - AWS Console (RDS Query Editor)**:
1. Go to RDS Console
2. Select `sipap-dev-rds` instance
3. Click "Query Editor"
4. Connect with Secrets Manager secret
5. Run: `SELECT tablename FROM pg_tables WHERE schemaname = 'public';`

**Expected Result**: 10 tables (users, sports, leagues, teams, matches, odds, predictions, intelligence_sources, user_subscriptions, audit_log)

**Time Estimate**: 5 minutes

---

### 5. Future: Set up Alembic (Optional) ⏳

**Purpose**: Version-controlled schema migrations for future updates.

**Why Alembic?**
- Track schema changes over time
- Upgrade/downgrade capability
- Auto-generate migrations from SQLAlchemy models
- Team collaboration (everyone applies same migrations)

**Implementation Plan**:
1. Install Alembic in migration container
2. Initialize Alembic in `database/alembic/`
3. Create initial migration from current schema
4. Update `run-migration.sh` to run Alembic migrations
5. Document Alembic workflow

**Time Estimate**: 2-3 hours (future task)

---

## Success Criteria

### Phase 1: CI/CD Setup (Current) ✅
- [x] Comprehensive documentation (`README.md`, `SETUP.md`, `MIGRATION-SUMMARY.md`)
- [x] GitHub Actions workflow configured
- [x] Docker image architecture explained (amd64 requirement)
- [x] Sentinel patterns studied and applied

### Phase 2: Image Build (Next) ⏳
- [ ] GitHub Actions secrets configured (`AWS_ROLE_ARN`)
- [ ] Workflow tested successfully
- [ ] Image available in ECR (`sipap-migrations:latest`)
- [ ] Image digest verified (SHA256)

### Phase 3: Migration Execution (Next) ⏳
- [ ] ECS task executed successfully
- [ ] CloudWatch logs show success
- [ ] Exit code = 0
- [ ] 10 tables verified in RDS

### Phase 4: Data Verification (Next) ⏳
- [ ] Schema matches `schema.sql`
- [ ] 4 sports inserted
- [ ] 5 leagues inserted
- [ ] Application can connect to database

---

## Cost Impact

### Before Migration
- **RDS**: Standard RDS (db.t4g.micro) running but empty
- **ECR**: Repository created (no storage cost until image pushed)
- **ECS**: Task definition registered (no cost until executed)
- **Total**: ~$12/month (RDS only)

### After Migration
- **RDS**: Standard RDS with schema + seed data (~$12/month)
- **ECR**: Docker image (~500 MB compressed) (~$0.02/month storage)
- **ECS**: One-time task execution (~$0.01 for 2-5 minutes runtime)
- **CloudWatch Logs**: 7-day retention (~$0.01/month)
- **Total**: ~$12.04/month (minimal increase)

### Ongoing (Future Migrations)
- **ECS Task Execution**: $0.01 per migration run
- **ECR Storage**: $0.02/month (one image)
- **GitHub Actions**: Free for public repos, included in GitHub Pro/Team for private repos

---

## Questions to Clarify

Before proceeding, please confirm:

1. **GitHub Repository**:
   - Is `sipap-terraform` in a GitHub repository?
   - Is it public or private?
   - What is the org/repo name (e.g., `odira/sipap-terraform`)?

2. **AWS IAM OIDC Provider**:
   - Has this been set up before for other projects?
   - Do you want me to create the IAM role, or will you handle it manually?

3. **Workflow Trigger Preference**:
   - Automatic on push to `main`? (current config)
   - Manual trigger only?
   - Both?

4. **Database Access**:
   - Do you have a bastion host or VPN for direct database access?
   - Or should we verify via CloudWatch logs only?

---

## References

- **Database Migration Guide**: `database/README.md`
- **GitHub Actions Setup**: `.github/SETUP.md`
- **Terraform Infrastructure**: `migrations.tf`
- **Sentinel Reference**: `/Users/charlesotuya/AI-Odi/sentinel/repos/sentinel-master/.github/workflows/deploy-orchestrator-deltekdev.yml`
- **Sentinel Config Reference**: `/Users/charlesotuya/AI-Odi/sentinel/repos/sentinel-terraform-master/sentinel_gce/env_vars/deltekdev.tfvars`

---

**Ready to proceed?** Let me know if you'd like me to help with:
1. Creating the IAM role for GitHub Actions
2. Testing the workflow after secrets are configured
3. Running the migration after the image is built
4. Setting up Alembic for future migrations
