# SIPAP Batch Scraper Events Infrastructure

This directory contains Terraform configuration for deploying scheduled batch scraper jobs using Lambda, ECS Fargate, and EventBridge.

## Overview

This infrastructure deploys 3 scheduled jobs:

1. **Daily Harvest** (ECS Fargate) - Scrapes detailed match data from 13 competitions
   - Schedule: Daily at 12:00 AM UTC
   - Runtime: ~3 minutes
   - Cost: $0.05/month

2. **Odds Updater** (Lambda) - Updates betting odds for upcoming matches
   - Schedule: Daily at 9:00 AM UTC
   - Runtime: ~2 minutes
   - Cost: $0.01/month

3. **Fixture Updater** (Lambda) - Updates fixtures, standings, and news
   - Schedule: Hourly
   - Runtime: ~2 minutes
   - Cost: $0.15/month

**Total Cost**: $0.21/month

## Architecture

This events infrastructure depends on resources created by the root terraform configuration:

- VPC, subnets, security groups
- Aurora PostgreSQL database
- ElastiCache Redis cluster
- ECS cluster
- ECR repositories
- Secrets Manager secrets (Aurora credentials + API keys)

## Resources Created

### IAM Roles
- `sipap-dev-batch-scraper-lambda-role` - Lambda execution role with Secrets Manager access
- `sipap-dev-batch-scraper-ecs-task-role` - ECS task role with Secrets Manager access
- `sipap-dev-batch-scraper-eventbridge-role` - EventBridge role for invoking Lambda and ECS tasks

### Lambda Functions
- `sipap-dev-odds-updater` - ARM64, 1024 MB, 3-minute timeout
- `sipap-dev-fixture-updater` - ARM64, 1024 MB, 3-minute timeout

### ECS Task Definition
- `sipap-dev-daily-harvest` - Fargate, 0.25 vCPU, 0.5 GB memory

### EventBridge Schedules
- `sipap-dev-daily-harvest-schedule` - cron(0 0 * * ? *)
- `sipap-dev-odds-updater-schedule` - cron(0 9 * * ? *)
- `sipap-dev-fixture-updater-schedule` - rate(1 hour)

### CloudWatch Log Groups
- `/aws/lambda/sipap-dev-odds-updater` - 7-day retention
- `/aws/lambda/sipap-dev-fixture-updater` - 7-day retention
- `/ecs/sipap-dev-daily-harvest` - 7-day retention

## Prerequisites

Before deploying this infrastructure, ensure the following are complete:

### 1. Root Infrastructure Deployed
```bash
cd .sipap/repos/sipap-terraform
terraform apply
```

This creates:
- VPC, subnets, security groups
- Aurora database with credentials secret
- ElastiCache Redis cluster
- ECS cluster
- ECR repository for batch-scraper
- API keys secret (empty, to be populated manually)

### 2. API Keys Secret Populated
```bash
# Get the CLI command from root terraform outputs
cd .sipap/repos/sipap-terraform
terraform output populate_api_keys_cli_command

# Execute the command with your actual API keys
aws secretsmanager put-secret-value \
  --secret-id sipap/dev/api-keys \
  --secret-string '{"FOOTBALL_DATA_KEY":"your_key_here","ODDS_API_KEY":"your_key_here","THESPORTSDB_KEY":"123"}' \
  --profile odiraaws \
  --region us-east-1
```

### 3. Lambda Deployment Packages Built
```bash
cd .sipap/repos/sipap-batch-scraper
./scripts/build_lambda_packages.sh
```

This creates:
- `../sipap-terraform/events/lambda_packages/odds_updater.zip`
- `../sipap-terraform/events/lambda_packages/fixture_updater.zip`

### 4. Docker Image Built and Pushed to ECR
```bash
cd sipap/repos/sipap-batch-scraper

# Get ECR repository URL from root terraform
ECR_REPO=$(cd ../sipap-terraform && terraform output -raw ecr_repository_urls | jq -r '.["batch-scraper"]')

# Build and push Docker image
docker build -t sipap-batch-scraper:latest .
docker tag sipap-batch-scraper:latest $ECR_REPO:latest
aws ecr get-login-password --region us-east-1 --profile odiraaws | \
  docker login --username AWS --password-stdin $ECR_REPO
docker push $ECR_REPO:latest
```

## Deployment Instructions

### Step 1: Initialize Terraform
```bash
cd sipap/repos/sipap-terraform/events

# Initialize Terraform (first time only)
terraform init

# Verify terraform.tfvars if needed
cat > terraform.tfvars <<EOF
stack_name  = "sipap"
env         = "dev"
aws_region  = "us-east-1"
odds_updater_deployment_package    = "./lambda_packages/odds_updater.zip"
fixture_updater_deployment_package = "./lambda_packages/fixture_updater.zip"
EOF
```

### Step 2: Plan and Apply
```bash
# Review what will be created
terraform plan -out=tfplan

# Apply the changes
terraform apply tfplan
```

### Step 3: Verify Deployment
```bash
# List EventBridge rules
aws events list-rules --name-prefix sipap-dev- --profile odiraaws --region us-east-1

# Check Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `sipap-dev`)].FunctionName' --profile odiraaws --region us-east-1

# Verify ECS task definition
aws ecs describe-task-definition --task-definition sipap-dev-daily-harvest --profile odiraaws --region us-east-1
```

### Step 4: Manual Test Invocations
```bash
# Test Odds Updater Lambda
aws lambda invoke \
  --function-name sipap-dev-odds-updater \
  --payload '{}' \
  --profile odiraaws \
  --region us-east-1 \
  response.json

# Test Fixture Updater Lambda
aws lambda invoke \
  --function-name sipap-dev-fixture-updater \
  --payload '{}' \
  --profile odiraaws \
  --region us-east-1 \
  response.json

# Test Daily Harvest ECS Task (get cluster ARN first)
CLUSTER_ARN=$(terraform output -raw ../ecs_cluster_name)
TASK_DEF_ARN=$(terraform output -raw daily_harvest_task_definition_arn)
# ... (see deployment guide for full command)
```

### Step 5: Monitor Execution
```bash
# Tail Lambda logs
aws logs tail /aws/lambda/sipap-dev-odds-updater --follow --profile odiraaws --region us-east-1
aws logs tail /aws/lambda/sipap-dev-fixture-updater --follow --profile odiraaws --region us-east-1

# Tail Fargate logs
aws logs tail /ecs/sipap-dev-daily-harvest --follow --profile odiraaws --region us-east-1
```

## Updating Lambda Functions

When you make changes to Lambda function code:

### Option 1: Rebuild and Reapply (Recommended)
```bash
cd .sipap/repos/sipap-batch-scraper

# Rebuild Lambda packages
./scripts/build_lambda_packages.sh

# Terraform will detect the source_code_hash change and redeploy
cd ../sipap-terraform/events
terraform apply
```

### Option 2: Update via AWS CLI (Quick Updates)
```bash
cd .sipap/repos/sipap-batch-scraper

# Rebuild packages
./scripts/build_lambda_packages.sh

# Update via AWS CLI
aws lambda update-function-code \
  --function-name sipap-dev-odds-updater \
  --zip-file fileb://../sipap-terraform/events/lambda_packages/odds_updater.zip \
  --profile odiraaws \
  --region us-east-1
```

## Updating Docker Image

When you make changes to the daily harvest job:

```bash
cd .sipap/repos/sipap-batch-scraper

# Get ECR repository URL
ECR_REPO=$(cd ../sipap-terraform && terraform output -raw ecr_repository_urls | jq -r '.["batch-scraper"]')

# Rebuild and push
docker build -t sipap-batch-scraper:latest .
docker tag sipap-batch-scraper:latest $ECR_REPO:latest
aws ecr get-login-password --region us-east-1 --profile odiraaws | \
  docker login --username AWS --password-stdin $ECR_REPO
docker push $ECR_REPO:latest

# ECS will use the new image on the next scheduled run
# To force immediate update, manually run the task (see deployment guide)
```

## Troubleshooting

### Lambda Timeout
If Lambda functions timeout:
```bash
aws lambda update-function-configuration \
  --function-name sipap-dev-odds-updater \
  --timeout 300 \
  --profile odiraaws \
  --region us-east-1
```

### Secrets Manager Access Denied
Verify IAM roles have correct permissions:
```bash
aws iam get-role-policy \
  --role-name sipap-dev-batch-scraper-lambda-role \
  --policy-name secrets-manager-access \
  --profile odiraaws \
  --region us-east-1
```

### API Rate Limiting
Check API usage:
```bash
# The Odds API shows usage in response headers
curl -X GET "https://api.the-odds-api.com/v4/sports?apiKey=${ODDS_API_KEY}"
```

### Docker Image Pull Failure
1. Verify ECR image exists
2. Check ECS execution role has ECR permissions
3. Verify VPC has route to ECR service endpoint

## Cost Monitoring

Expected monthly costs:
- Fargate daily harvest: $0.05/month (0.25 vCPU, 0.5 GB, 3 min/day)
- Lambda odds updater: $0.01/month (1024 MB, 2 min/day, ARM64)
- Lambda fixture updater: $0.15/month (1024 MB, 2 min/hour, ARM64)

Total: **$0.21/month** infrastructure + **$0/month** APIs (free tier)

## Rollback Procedure

### Disable All Jobs
```bash
aws events disable-rule --name sipap-dev-daily-harvest-schedule --profile odiraaws --region us-east-1
aws events disable-rule --name sipap-dev-odds-updater-schedule --profile odiraaws --region us-east-1
aws events disable-rule --name sipap-dev-fixture-updater-schedule --profile odiraaws --region us-east-1
```

### Delete Resources
```bash
cd .sipap/repos/sipap-terraform/events
terraform destroy
```

## Dependencies

This events infrastructure depends on the root terraform state:

```hcl
data "terraform_remote_state" "root" {
  backend = "s3"
  config = {
    bucket  = "sipap-dev-tf-state-bucket"
    key     = "sipap-dev-tf-state"
    profile = "odiraaws"
    region  = "us-west-1"
  }
}
```

Required outputs from root state:
- `vpc_id`, `private_subnet_ids`, `ecs_tasks_sg_id`
- `aurora_credentials_secret_arn`, `api_keys_secret_arn`
- `ecs_cluster_name`, `ecs_task_execution_role_arn`
- `elasticache_endpoint`
- `ecr_repository_urls["batch-scraper"]`

## Version History

- **v1.0** (2026-06-28) - Initial deployment
  - 3 scheduled jobs (daily harvest, odds updater, fixture updater)
  - EventBridge schedules
  - ARM64 Lambda functions
  - Fargate task for daily harvest

---

**Last Updated**: 2026-06-28
**Terraform Version**: >= 1.10.0
**AWS Provider Version**: ~> 5.91
