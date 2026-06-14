# GitHub Actions Setup Guide

## Overview

This repository uses GitHub Actions to automate the build and deployment of the database migration Docker image to Amazon ECR.

---

## Required GitHub Secrets

### 1. `AWS_ROLE_ARN`

**Purpose**: IAM role ARN for OIDC authentication to AWS.

**Format**: `arn:aws:iam::810278669998:role/<role-name>`

**How to Create**:

```bash
# 1. Create IAM OIDC Identity Provider (one-time setup)
aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --profile odiraaws

# 2. Create IAM role for GitHub Actions
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::810278669998:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<your-github-org>/<repo-name>:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
    --role-name github-actions-sipap-migrations \
    --assume-role-policy-document file://trust-policy.json \
    --profile odiraaws

# 3. Attach ECR permissions policy
cat > ecr-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages",
        "ecs:RegisterTaskDefinition",
        "ecs:DescribeTaskDefinition",
        "ecs:ListTaskDefinitions"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name github-actions-sipap-migrations \
    --policy-name ECRAccess \
    --policy-document file://ecr-policy.json \
    --profile odiraaws

# 4. Get the role ARN
aws iam get-role \
    --role-name github-actions-sipap-migrations \
    --query 'Role.Arn' \
    --output text \
    --profile odiraaws
```

**Add to GitHub**:
1. Go to: `https://github.com/<org>/<repo>/settings/secrets/actions`
2. Click "New repository secret"
3. Name: `AWS_ROLE_ARN`
4. Value: `arn:aws:iam::810278669998:role/github-actions-sipap-migrations`
5. Click "Add secret"

---

## Workflow Configuration

The workflow is located at: `.github/workflows/build-migration-image.yml`

### Trigger Conditions

**Automatic Triggers**:
- Push to `main` branch when files in `database/` directory change
- Changes to the workflow file itself

**Manual Trigger**:
1. Go to: `https://github.com/<org>/<repo>/actions`
2. Select "Build & Push Database Migration Image"
3. Click "Run workflow"
4. Choose branch (default: `main`)
5. Optionally check "Force build even without changes"
6. Click "Run workflow"

---

## Workflow Steps

The workflow performs the following steps:

1. **Checkout repository**: Clones the code
2. **Configure AWS Credentials**: Uses OIDC to assume the IAM role
3. **Verify AWS Identity**: Confirms AWS authentication
4. **Login to Amazon ECR**: Authenticates Docker with ECR
5. **Set up Docker Buildx**: Enables multi-platform builds
6. **Build and Push Image**: Builds Docker image for `linux/amd64` and pushes to ECR
7. **Get Image Digest**: Retrieves the SHA256 digest of the pushed image
8. **Force Update ECS Task Definition**: Registers new task definition revision (forces ECS to pull new image)
9. **Build Summary**: Creates GitHub Actions summary with next steps

---

## Testing the Workflow

### Local Testing (Docker Build Only)

```bash
cd sipap-terraform/database

# Build locally (for testing only - use GitHub Actions for production)
docker build --platform linux/amd64 -t sipap-migrations:test .

# Verify build
docker images sipap-migrations:test
```

**Note**: Do NOT push from local machine - use GitHub Actions to ensure amd64 architecture.

---

### Production Testing (GitHub Actions)

1. **Make a test change**:
   ```bash
   cd sipap-terraform/database
   echo "# Test change" >> README.md
   git add README.md
   git commit -m "Test GitHub Actions workflow"
   git push origin main
   ```

2. **Monitor workflow**:
   - Go to: `https://github.com/<org>/<repo>/actions`
   - Click on the running workflow
   - Watch steps execute in real-time

3. **Verify ECR image**:
   ```bash
   aws ecr describe-images \
       --repository-name sipap-migrations \
       --region us-east-1 \
       --profile odiraaws \
       --query 'imageDetails[0].{digest:imageDigest,tags:imageTags,pushedAt:imagePushedAt}'
   ```

4. **Run migration**:
   ```bash
   cd sipap-terraform/
   TASK_DEF=$(terraform output -raw migrations_task_definition)
   PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r 'join(",")')
   DB_SG=$(terraform output -raw ecs_tasks_sg_id)

   aws ecs run-task \
       --cluster sipap-dev-cluster \
       --task-definition $TASK_DEF \
       --launch-type FARGATE \
       --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$DB_SG],assignPublicIp=DISABLED}" \
       --region us-east-1 \
       --profile odiraaws
   ```

5. **Monitor logs**:
   ```bash
   aws logs tail /ecs/sipap-dev-migrations \
       --follow \
       --format short \
       --region us-east-1 \
       --profile odiraaws
   ```

---

## Troubleshooting

### Issue: "Error: Could not assume role"

**Symptom**: GitHub Actions fails at "Configure AWS Credentials" step.

**Cause**: IAM role trust policy doesn't trust GitHub Actions OIDC provider.

**Solution**: Verify trust policy includes correct GitHub repository:
```bash
aws iam get-role \
    --role-name github-actions-sipap-migrations \
    --query 'Role.AssumeRolePolicyDocument' \
    --profile odiraaws
```

Update the `StringLike` condition to match your repository:
```json
"token.actions.githubusercontent.com:sub": "repo:YourOrg/sipap-terraform:*"
```

---

### Issue: "denied: Your authorization token has expired"

**Symptom**: Docker push fails with authorization error.

**Cause**: ECR login token expired (valid for 12 hours).

**Solution**: Workflow automatically handles this via `amazon-ecr-login@v2` action. If running locally, re-run:
```bash
aws ecr get-login-password --region us-east-1 --profile odiraaws | \
    docker login --username AWS --password-stdin 810278669998.dkr.ecr.us-east-1.amazonaws.com
```

---

### Issue: "Image not found in ECR after push"

**Symptom**: Image pushed successfully but not visible in ECR.

**Cause**: Pushed to wrong repository or region.

**Solution**: Verify repository name and region:
```bash
# List ECR repositories
aws ecr describe-repositories \
    --region us-east-1 \
    --profile odiraaws \
    --query 'repositories[*].repositoryName'

# Verify image in correct repository
aws ecr list-images \
    --repository-name sipap-migrations \
    --region us-east-1 \
    --profile odiraaws
```

---

## Security Best Practices

1. **Use OIDC, not access keys**: OIDC tokens are short-lived and scoped to specific workflows
2. **Minimal IAM permissions**: Role only has ECR and ECS task definition permissions
3. **Repository scoping**: Trust policy limits to specific GitHub repository
4. **Secret rotation**: OIDC tokens auto-rotate (no manual rotation needed)
5. **Audit logging**: CloudTrail logs all IAM role assumptions

---

## Monitoring and Alerts

### CloudWatch Alarms (Optional)

Create alarms for migration failures:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name sipap-migrations-failure \
    --alarm-description "Alert when database migration fails" \
    --metric-name ExitCode \
    --namespace AWS/ECS \
    --statistic Maximum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=ClusterName,Value=sipap-dev-cluster Name=TaskDefinitionFamily,Value=sipap-dev-migrations \
    --profile odiraaws
```

### GitHub Actions Notifications

Enable notifications:
1. Go to: `https://github.com/<org>/<repo>/settings/notifications`
2. Enable "Actions" notifications
3. Choose notification method (email, Slack, etc.)

---

## Next Steps

1. **Set up GitHub secret**: Add `AWS_ROLE_ARN` secret to repository
2. **Test workflow**: Push a change to `database/` directory
3. **Verify image**: Check ECR for new image
4. **Run migration**: Execute ECS task to apply schema
5. **Monitor logs**: Verify migration success in CloudWatch

For detailed migration instructions, see: `database/README.md`
