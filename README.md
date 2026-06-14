# SIPAP Terraform Infrastructure

AWS infrastructure for Sports Intelligence Platform and Outcome Probability Assessment Platform.

## Overview

This repository contains Terraform configuration for deploying SIPAP infrastructure on AWS, following Sentinel's proven modular patterns.

## Architecture

### Infrastructure Components

- **VPC**: 172.31.0.0/16 (dev), 172.20.0.0/16 (staging), 10.23.0.0/16 (prod)
- **Subnets**: 3 public + 3 private across 3 AZs
- **Database**: Aurora Serverless v2 PostgreSQL (0.5-1 ACU for dev)
- **Cache**: ElastiCache Serverless Redis
- **Compute**: ECS Fargate cluster (services added in Phase 4)
- **Container Registry**: ECR (7 repositories)
- **Queues**: SQS (prediction queue + DLQ)

### Repository Structure

```
sipap-terraform/
├── backend.tf              # S3 backend configuration
├── providers.tf            # AWS provider setup
├── main.tf                 # Main orchestration
├── variables.tf            # Global variables
├── outputs.tf              # Global outputs
├── modules/                # Terraform modules
│   ├── vpc/               # VPC creation
│   ├── subnets/           # Subnets creation
│   ├── internet_gateway/  # Internet Gateway
│   ├── nat_gateway/       # NAT Gateways
│   ├── rds/               # Aurora Serverless v2
│   ├── ecs/               # ECS Fargate
│   ├── alb/               # Load Balancer
│   ├── ecr/               # Container Registry
│   ├── elasticache/       # Redis cache
│   ├── lambda/            # Lambda functions
│   ├── security_groups/   # Security groups
│   ├── sqs/               # SQS queues
│   ├── role/              # IAM roles
│   ├── policies/          # IAM policies
│   ├── assume_role_policies/ # Assume role policies
│   ├── parameter_store/   # SSM Parameter Store
│   └── api_gateway/       # API Gateway
├── environments/
│   └── dev.tfvars         # Development config
└── database/
    ├── schema.sql         # Database schema (10 tables)
    ├── seed_data.sql      # Initial seed data
    └── migrations/        # Alembic migrations (TODO)
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- S3 bucket: `sipap-terraform-state`
- DynamoDB table: `sipap-terraform-locks`

### Create S3 Backend Resources

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://sipap-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket sipap-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket sipap-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name sipap-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Deployment

### 1. Initialize Terraform

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform
terraform init
```

### 2. Validate Configuration

```bash
terraform validate
terraform fmt -recursive
```

### 3. Plan Deployment

```bash
# Development
terraform plan -var-file=environments/dev.tfvars

# View detailed plan
terraform plan -var-file=environments/dev.tfvars -out=dev.tfplan
terraform show dev.tfplan
```

### 4. Apply Infrastructure

```bash
# Apply the plan
terraform apply -var-file=environments/dev.tfvars

# Or apply saved plan
terraform apply dev.tfplan
```

### 5. Run Database Migrations

```bash
# Get Aurora endpoint and password
export DB_ENDPOINT=$(terraform output -raw aurora_cluster_endpoint)
export DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id sipap-dev-aurora-password \
  --query SecretString --output text)

# Run schema creation
psql "postgresql://sipap_admin:${DB_PASSWORD}@${DB_ENDPOINT}/sipap_dev" < database/schema.sql

# Run seed data
psql "postgresql://sipap_admin:${DB_PASSWORD}@${DB_ENDPOINT}/sipap_dev" < database/seed_data.sql

# Verify
psql "postgresql://sipap_admin:${DB_PASSWORD}@${DB_ENDPOINT}/sipap_dev" -c "\dt"
psql "postgresql://sipap_admin:${DB_PASSWORD}@${DB_ENDPOINT}/sipap_dev" -c "SELECT * FROM sports;"
```

## Database Schema

### Tables

1. **users** - User accounts and subscriptions
2. **sports** - Sports catalog (soccer, nba, nfl, tennis)
3. **leagues** - Sports leagues (Premier League, La Liga, etc.)
4. **teams** - Team data
5. **matches** - Match schedule and results
6. **predictions** - AI predictions with confidence scores
7. **prediction_evidence** - Evidence attribution from MCP servers
8. **agent_contributions** - Agent-specific predictions
9. **user_feedback** - User ratings on predictions
10. **subscription_events** - Billing events (Stripe)

## Cost Estimates

### Development Environment (Fully Cost Optimized ✅)

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| **RDS PostgreSQL** | **db.t4g.micro (optimized)** | **~$12** |
| **ElastiCache Redis** | **cache.t4g.micro (optimized)** | **~$13** |
| **NAT Gateway** | **1 gateway (optimized)** | **$33** |
| Data Transfer | 100 GB/mo | $9 |
| ECS Fargate | (no services yet) | $0 |
| ECR Storage | <1 GB | <$1 |
| SQS | Minimal usage | <$1 |
| **Total** | | **~$67-68/mo** |

**Cost Optimizations Applied (Option B - Aggressive):**
1. ✅ NAT Gateways: 3 → 1 gateway → **Saves $66/mo**
2. ✅ Database: Aurora Serverless v2 → RDS db.t4g.micro → **Saves $31-75/mo**
3. ✅ Cache: ElastiCache Serverless → cache.t4g.micro → **Saves $11/mo**

**Total Savings: $108-152/mo** (69% cost reduction from original ~$175-220/mo)

**For Production (restore serverless):**
```hcl
# In environments/prod.tfvars
aurora_use_serverless      = true   # Switch to Aurora Serverless v2
elasticache_use_serverless = true   # Switch to ElastiCache Serverless
nat_gateway_count          = 3      # High availability
```

## Outputs

After deployment, Terraform will output:

- `vpc_id` - VPC ID
- `public_subnet_ids` - Public subnet IDs
- `private_subnet_ids` - Private subnet IDs
- `aurora_cluster_endpoint` - Aurora connection endpoint (sensitive)
- `aurora_database_name` - Database name
- `elasticache_endpoint` - Redis endpoint (sensitive)
- `ecr_repository_urls` - Container image repository URLs
- `ecs_cluster_name` - ECS cluster name
- `prediction_queue_url` - SQS queue URL

## Security

- Database credentials stored in AWS Secrets Manager
- All data resources in private subnets
- Security groups restrict access to VPC CIDR only
- S3 state bucket encrypted at rest
- Aurora encryption at rest enabled
- ECR images encrypted with AES256

## Maintenance

### Update Database Schema

```bash
# Using psql
psql $DATABASE_URL < database/new_migration.sql

# Or using Alembic (TODO: Phase 1)
cd database
alembic revision --autogenerate -m "Description"
alembic upgrade head
```

### Destroy Environment (DEV ONLY)

```bash
# WARNING: This will destroy all infrastructure
terraform destroy -var-file=environments/dev.tfvars
```

## Next Steps (Phase 2)

1. Build 5 Data MCP Servers (using sipap-serverlesshandler-mcp)
2. Deploy MCP servers to Lambda/ECS Fargate
3. Test infrastructure connectivity

## References

- **Plan**: `~/.claude/plans/luminous-kindling-cray.md`
- **Sentinel Terraform**: `/Users/charlesotuya/AI-Odi/sentinel/repos/sentinel-terraform-master/sentinel_gce/`
- **SIPAP Architecture**: `/Users/charlesotuya/AI-Odi/sentinel/sipap/technical-architecture-v2.md`

## Support

For issues or questions: charles@sipap.com

---

**Version**: 1.0
**Last Updated**: 2026-06-13
**Phase**: 1 (Infrastructure) - Day 1 Complete
