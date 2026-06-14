#!/bin/bash
# Deploy and Run Database Migrations
# This script builds the migration container, pushes to ECR, and runs the ECS task

set -e

echo "========================================="
echo "SIPAP Database Migration Deployment"
echo "========================================="

# Configuration
AWS_PROFILE="odiraaws"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="810278669998"

# Change to database directory
cd "$(dirname "$0")"

echo ""
echo "Step 1: Applying Terraform changes..."
echo "---------------------------------------"
cd ..
terraform apply -var-file=environments/dev.tfvars -auto-approve

# Get ECR repository URL and task definition from Terraform
echo ""
echo "Step 2: Getting ECR repository URL..."
echo "---------------------------------------"
ECR_REPO=$(terraform output -raw migrations_repository_url)
TASK_DEF=$(terraform output -raw migrations_task_definition)

echo "ECR Repository: $ECR_REPO"
echo "Task Definition: $TASK_DEF"

# Login to ECR
echo ""
echo "Step 3: Logging in to ECR..."
echo "---------------------------------------"
aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build Docker image
echo ""
echo "Step 4: Building migration container..."
echo "---------------------------------------"
cd database
docker build -t sipap-migrations:latest .

# Tag for ECR
docker tag sipap-migrations:latest $ECR_REPO:latest

# Push to ECR
echo ""
echo "Step 5: Pushing to ECR..."
echo "---------------------------------------"
docker push $ECR_REPO:latest

# Get VPC and subnet configuration
echo ""
echo "Step 6: Getting VPC configuration..."
echo "---------------------------------------"
cd ..
PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r '.[]' | paste -sd,)
DB_SG=$(terraform output -raw ecs_tasks_sg_id)  # Use ECS tasks SG which has access to RDS

echo "Private Subnets: $PRIVATE_SUBNETS"
echo "Security Group: $DB_SG"

# Run ECS task
echo ""
echo "Step 7: Running migration ECS task..."
echo "---------------------------------------"
TASK_ARN=$(aws ecs run-task \
    --cluster sipap-dev-cluster \
    --task-definition $TASK_DEF \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$DB_SG],assignPublicIp=DISABLED}" \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Task started: $TASK_ARN"

# Wait for task to complete
echo ""
echo "Step 8: Waiting for migration to complete..."
echo "---------------------------------------"
echo "Monitoring task logs..."

# Extract task ID from ARN
TASK_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')

# Wait a few seconds for logs to start
sleep 10

# Stream logs
aws logs tail /ecs/sipap-dev-migrations \
    --follow \
    --format short \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --filter-pattern "migrations/$TASK_ID" || true

# Check final task status
echo ""
echo "Step 9: Checking final status..."
echo "---------------------------------------"
TASK_STATUS=$(aws ecs describe-tasks \
    --cluster sipap-dev-cluster \
    --tasks $TASK_ARN \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'tasks[0].lastStatus' \
    --output text)

EXIT_CODE=$(aws ecs describe-tasks \
    --cluster sipap-dev-cluster \
    --tasks $TASK_ARN \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

echo "Task Status: $TASK_STATUS"
echo "Exit Code: $EXIT_CODE"

if [ "$EXIT_CODE" == "0" ]; then
    echo ""
    echo "========================================="
    echo "✅ Migration completed successfully!"
    echo "========================================="
    exit 0
else
    echo ""
    echo "========================================="
    echo "❌ Migration failed with exit code: $EXIT_CODE"
    echo "========================================="
    exit 1
fi
