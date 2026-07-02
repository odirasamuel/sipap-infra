# Batch Scraper Terraform Deployment Guide

**Version:** 2.0
**Date:** 2026-06-28
**Status:** Ready for Deployment

---

## Overview

This guide documents the terraform deployment of 3 scheduled batch scraper jobs to AWS:

1. **Daily Harvest** - Fargate task (runs daily at 12:00 AM UTC)
2. **Odds Updater** - Lambda function (runs daily at 9:00 AM UTC)
3. **Fixture Updater** - Lambda function (runs hourly)

**Total Infrastructure Cost:** $0.21/month
**Total API Cost:** $0/month (all free tier)

---

## Architecture

The batch scraper infrastructure is split across two terraform configurations:

1. **Root terraform (`sipap-terraform/`)** - Core infrastructure
   - VPC, subnets, security groups
   - Aurora PostgreSQL database
   - ElastiCache Redis cluster
   - ECS cluster
   - ECR repositories (including `batch-scraper`)
   - **Secrets Manager** (Aurora credentials + API keys)

2. **Events terraform (`sipap-terraform/events/`)** - Scheduled jobs
   - IAM roles for Lambda, ECS, EventBridge
   - Lambda functions (odds_updater, fixture_updater)
   - ECS task definition (daily_harvest)
   - EventBridge schedules
   - CloudWatch log groups

This follows the Sentinel pattern where events/batch jobs are separate from core infrastructure.

---

## Prerequisites

### 1. AWS Resources (Already Deployed via Root Terraform)

The main SIPAP infrastructure must already be deployed:
- ✅ VPC with public/private subnets
- ✅ Security groups
- ✅ Aurora PostgreSQL cluster
- ✅ ElastiCache Redis cluster
- ✅ ECS cluster
- ✅ ECR repositories (including `batch-scraper`)
- ✅ Secrets Manager secrets (Aurora credentials + API keys - empty)

### 2. Local Tools Required

- AWS CLI configured with profile `odiraaws`
- Docker (for building Fargate image)
- Python 3.12+ (for building Lambda packages)
- Terraform 1.5+ (for infrastructure deployment)

### 3. API Keys

Obtain free tier API keys from:

1. **Football-Data.org**
   - Register at: https://www.football-data.org/client/register
   - Free tier: 10 requests/minute, FREE forever
   - Coverage: 13 competitions

2. **The Odds API**
   - Register at: https://the-odds-api.com/
   - Free tier: 500 credits/month
   - Coverage: 9 soccer leagues

3. **TheSportsDB**
   - Use `"123"` for free tier (public test key)
   - Or get premium key at: https://www.thesportsdb.com/api.php

---

## Deployment Steps

### Step 1: Deploy Root Infrastructure

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform

# Initialize terraform (first time only)
terraform init

# Review what will be created
terraform plan

# Apply the root infrastructure
terraform apply
```

**Resources created:**
- VPC, subnets, NAT gateway
- Security groups
- Aurora PostgreSQL database
- ElastiCache Redis cluster
- ECS cluster
- ECR repositories (including `batch-scraper`)
- **Aurora credentials secret** (auto-populated)
- **API keys secret** (empty - to be populated manually)
- SQS queues

### Step 2: Populate API Keys Secret

**IMPORTANT:** The API keys secret is created empty and must be populated manually via AWS CLI with profile `odiraaws`.

```bash
# Get the CLI command from terraform outputs
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform
terraform output populate_api_keys_cli_command

# Execute the command with your actual API keys
aws secretsmanager put-secret-value \
  --secret-id sipap/dev/api-keys \
  --secret-string '{"FOOTBALL_DATA_KEY":"your_actual_football_data_api_key","ODDS_API_KEY":"your_actual_odds_api_key","THESPORTSDB_KEY":"123"}' \
  --profile odiraaws \
  --region us-east-1
```

**Verify the secret was populated:**
```bash
aws secretsmanager get-secret-value \
  --secret-id sipap/dev/api-keys \
  --query SecretString \
  --output text \
  --profile odiraaws \
  --region us-east-1 | jq
```

**Expected output:**
```json
{
  "FOOTBALL_DATA_KEY": "your_actual_football_data_api_key",
  "ODDS_API_KEY": "your_actual_odds_api_key",
  "THESPORTSDB_KEY": "123"
}
```

### Step 3: Deploy CI/CD Infrastructure

Deploy the S3 bucket for Lambda packages and GitHub Actions IAM role:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra

# Initialize terraform (first time only)
terraform init

# Review what will be created
terraform plan

# Apply the CI/CD infrastructure
terraform apply
```

**Resources created:**
- S3 bucket: `sipap-lambda-packages-dev` (with versioning, encryption, lifecycle policies)
- IAM role for GitHub Actions (OIDC-based)

**Get GitHub Actions Role ARN:**
```bash
terraform output github_actions_role_arn
```

Add this ARN as a secret to the sipap-batch-scraper repository:
- Secret name: `SIPAP_DEV_AWS_ROLE_ARN`
- Secret value: (ARN from terraform output)

### Step 4: Trigger Automated Builds (GitHub Actions)

**No manual builds required!** Push code to trigger automated builds:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-batch-scraper

git add .
git commit -m "Trigger automated builds"
git push origin main
```

This triggers two GitHub Actions workflows:
1. **Lambda Package Builder** - Builds and uploads to S3 (~3 minutes)
2. **Docker Image Builder** - Builds and pushes to ECR (~5 minutes)

**Monitor workflow execution:**
- GitHub: https://github.com/odirasamuel/sipap-batch-scraper/actions
- Or manually trigger: Actions → Select workflow → Run workflow

**Verify builds completed:**
```bash
# Check S3 Lambda packages
aws s3 ls s3://sipap-lambda-packages-dev/batch-scraper/ --profile odiraaws

# Check ECR Docker image
aws ecr describe-images \
  --repository-name sipap-dev-batch-scraper \
  --profile odiraaws \
  --region us-east-1
```

### Step 5: Deploy Events Infrastructure

Now deploy the Lambda functions, ECS task definition, and EventBridge schedules:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/events

# Initialize terraform (first time only)
terraform init

# Review what will be created
terraform plan

# Apply the events infrastructure
terraform apply
```

**Resources created:**
- 3 IAM roles (Lambda execution, ECS task, EventBridge)
- 2 Lambda functions (odds_updater, fixture_updater)
- 1 ECS task definition (daily_harvest)
- 3 EventBridge rules (daily harvest, odds updater, fixture updater)
- 3 EventBridge targets
- 3 CloudWatch log groups

### Step 6: Test Manual Invocations

Before relying on scheduled execution, test each job manually.

**Test Odds Updater Lambda:**
```bash
aws lambda invoke \
  --function-name sipap-dev-odds-updater \
  --payload '{}' \
  --profile odiraaws \
  --region us-east-1 \
  response.json

cat response.json
```

**Expected output:**
```json
{
  "statusCode": 200,
  "body": "{\"status\": \"success\", \"odds_updated\": 10, \"duration_ms\": 1500}"
}
```

**Test Fixture Updater Lambda:**
```bash
aws lambda invoke \
  --function-name sipap-dev-fixture-updater \
  --payload '{}' \
  --profile odiraaws \
  --region us-east-1 \
  response.json

cat response.json
```

**Expected output:**
```json
{
  "statusCode": 200,
  "body": "{\"status\": \"success\", \"fixtures_updated\": 15, \"standings_updated\": 5, \"duration_ms\": 2000}"
}
```

**Test Daily Harvest ECS Task:**
```bash
# Get cluster and task definition from terraform outputs
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/events

CLUSTER_NAME=$(cd .. && terraform output -raw ecs_cluster_name)
TASK_DEF_ARN=$(terraform output -raw daily_harvest_task_definition_arn)
SUBNET_IDS=$(cd .. && terraform output -json private_subnet_ids | jq -r 'join(",")')
SG_ID=$(cd .. && terraform output -raw ecs_tasks_sg_id)

# Run task manually
aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEF_ARN \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SG_ID],assignPublicIp=DISABLED}" \
  --profile odiraaws \
  --region us-east-1
```

### Step 7: Monitor Execution

**View Lambda logs:**
```bash
# Odds updater logs
aws logs tail /aws/lambda/sipap-dev-odds-updater --follow --profile odiraaws --region us-east-1

# Fixture updater logs
aws logs tail /aws/lambda/sipap-dev-fixture-updater --follow --profile odiraaws --region us-east-1
```

**View Fargate logs:**
```bash
# Daily harvest logs
aws logs tail /ecs/sipap-dev-daily-harvest --follow --profile odiraaws --region us-east-1
```

### Step 8: Verify EventBridge Schedules

```bash
# List all SIPAP EventBridge rules
aws events list-rules --name-prefix sipap-dev- --profile odiraaws --region us-east-1

# Check specific rule targets
aws events list-targets-by-rule --rule sipap-dev-daily-harvest-schedule --profile odiraaws --region us-east-1
aws events list-targets-by-rule --rule sipap-dev-odds-updater-schedule --profile odiraaws --region us-east-1
aws events list-targets-by-rule --rule sipap-dev-fixture-updater-schedule --profile odiraaws --region us-east-1
```

---

## Updating Lambda Code

**Automated via GitHub Actions (Recommended)**

Just push your code changes:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-batch-scraper

# Make your changes
vim src/sipap_batch_scraper/jobs/odds_updater.py

# Commit and push
git add .
git commit -m "Update odds updater logic"
git push origin main

# GitHub Actions automatically:
# 1. Builds new Lambda packages
# 2. Uploads to S3
# 3. Updates Lambda functions
```

No manual steps required!

### Manual Update (Emergency Only)

If GitHub Actions is down:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-batch-scraper

# Build packages
./scripts/build_lambda_packages.sh

# Upload to S3
aws s3 cp ../sipap-terraform/lambda_packages/odds_updater.zip \
  s3://sipap-lambda-packages-dev/batch-scraper/ \
  --profile odiraaws

aws s3 cp ../sipap-terraform/lambda_packages/fixture_updater.zip \
  s3://sipap-lambda-packages-dev/batch-scraper/ \
  --profile odiraaws

# Update Lambda functions
aws lambda update-function-code \
  --function-name sipap-dev-odds-updater \
  --s3-bucket sipap-lambda-packages-dev \
  --s3-key batch-scraper/odds_updater.zip \
  --publish \
  --profile odiraaws \
  --region us-east-1

aws lambda update-function-code \
  --function-name sipap-dev-fixture-updater \
  --s3-bucket sipap-lambda-packages-dev \
  --s3-key batch-scraper/fixture_updater.zip \
  --publish \
  --profile odiraaws \
  --region us-east-1
```

---

## Updating Docker Image

**Automated via GitHub Actions (Recommended)**

Just push your code changes:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-batch-scraper

# Make your changes
vim src/sipap_batch_scraper/jobs/daily_harvest.py

# Commit and push
git add .
git commit -m "Update daily harvest job"
git push origin main

# GitHub Actions automatically:
# 1. Builds new Docker image
# 2. Pushes to ECR
# 3. Updates ECS task definition
```

No manual steps required!

### Manual Build and Push (Emergency Only)

If GitHub Actions is down:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-batch-scraper

# Get ECR repository URL
ECR_REPO=$(cd ../sipap-terraform && terraform output -json ecr_repository_urls | jq -r '.["batch-scraper"]')

# Build and push
docker build -t sipap-batch-scraper:latest .
docker tag sipap-batch-scraper:latest $ECR_REPO:latest
aws ecr get-login-password --region us-east-1 --profile odiraaws | \
  docker login --username AWS --password-stdin $ECR_REPO
docker push $ECR_REPO:latest

# Force new task definition revision
cd ../sipap-terraform/events
terraform apply -replace=aws_ecs_task_definition.daily_harvest
```

---

## Troubleshooting

### Lambda Timeout

**Symptom:** Lambda function times out after 3 minutes

**Solution:**
```bash
# Increase timeout to 5 minutes
aws lambda update-function-configuration \
  --function-name sipap-dev-odds-updater \
  --timeout 300 \
  --profile odiraaws \
  --region us-east-1
```

### Secrets Manager Access Denied

**Symptom:** Lambda or ECS task fails with "AccessDeniedException" when accessing secrets

**Solution:** Verify IAM roles have the correct permissions:

```bash
# Check Lambda execution role
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/events
terraform output batch_scraper_lambda_role_arn

# Verify role policies in AWS Console
```

### API Rate Limiting

**Symptom:** API calls returning 429 errors

**Solution:** Check API usage and adjust schedules if needed:

```bash
# Check The Odds API usage
curl -X GET "https://api.the-odds-api.com/v4/sports?apiKey=${ODDS_API_KEY}"
# Response headers include: x-requests-remaining, x-requests-used
```

### Docker Image Pull Failure

**Symptom:** ECS task fails with "CannotPullContainerError"

**Solution:**
1. Verify ECR image exists
2. Check ECS execution role has ECR permissions
3. Verify VPC has route to ECR service endpoint

---

## Cost Monitoring

### Expected Monthly Costs

| Component | Configuration | Monthly Cost |
|-----------|---------------|--------------|
| **Fargate Daily Harvest** | 0.25 vCPU, 0.5 GB, 3 min/day | $0.05 |
| **Lambda Odds Updater** | 1024 MB, 2 min/day, ARM64 | $0.01 |
| **Lambda Fixture Updater** | 1024 MB, 2 min/hour, ARM64 | $0.15 |
| **TOTAL** | | **$0.21/month** |

### Set Up Cost Alerts

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name sipap-batch-scraper-cost-alert \
  --alarm-description "Alert if batch scraper costs exceed $1/month" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 1.0 \
  --comparison-operator GreaterThanThreshold \
  --profile odiraaws \
  --region us-east-1
```

---

## Rollback Procedure

### Disable All Jobs

```bash
# Disable EventBridge rules (stops scheduled execution)
aws events disable-rule --name sipap-dev-daily-harvest-schedule --profile odiraaws --region us-east-1
aws events disable-rule --name sipap-dev-odds-updater-schedule --profile odiraaws --region us-east-1
aws events disable-rule --name sipap-dev-fixture-updater-schedule --profile odiraaws --region us-east-1
```

### Delete Resources via Terraform

```bash
# Delete events infrastructure first
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/events
terraform destroy

# Then delete root infrastructure if needed
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform
terraform destroy
```

---

## Deployment Checklist

**One-Time Setup:**
- [ ] Root infrastructure deployed (`sipap-terraform/`)
- [ ] API keys obtained from Football-Data.org and The Odds API
- [ ] API keys secret populated via AWS CLI with profile `odiraaws`
- [ ] CI/CD infrastructure deployed (`sipap-terraform/cicd_infra/`)
- [ ] GitHub secret `SIPAP_DEV_AWS_ROLE_ARN` configured

**Automated Deployment:**
- [ ] Code pushed to main branch (triggers GitHub Actions)
- [ ] Lambda packages uploaded to S3 (automated)
- [ ] Docker image pushed to ECR (automated)
- [ ] Events infrastructure deployed (`sipap-terraform/events/`)

**Verification:**
- [ ] Manual test invocations successful (all 3 jobs)
- [ ] EventBridge rules verified and enabled
- [ ] CloudWatch logs monitored for first 24 hours
- [ ] Cost monitoring and alerting configured

**Key Point:** After initial setup, just push code to main branch and everything deploys automatically.

---

**Deployment Status:** ⏳ READY - Awaiting manual deployment

**Estimated Deployment Time:** 1.5-2 hours

**Post-Deployment Monitoring:** 24-48 hours
