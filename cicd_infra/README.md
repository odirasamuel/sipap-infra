# CI/CD Infrastructure for sipap Lambda Deployments

This directory contains Terraform configuration for setting up GitHub Actions CI/CD infrastructure for automated Lambda deployments.

## Overview

This infrastructure enables:
- **GitHub OIDC Authentication**: Secure, credential-free deployments from GitHub Actions
- **S3-Based Lambda Packages**: Versioned storage for Lambda deployment packages
- **Multi-Repo Support**: Wildcard OIDC pattern supports all `sipap-*` repos in odirasamuel org
- **Environment Isolation**: Environment-specific S3 buckets (sipap-lambda-packages-dev, etc.)

## Resources Created

1. **S3 Bucket**: `sipap-lambda-packages-${var.env}`
   - Versioning enabled for rollback capability
   - Server-side encryption (AES256)
   - Public access blocked
   - Lifecycle policy: Delete old versions after 90 days

2. **GitHub OIDC Provider**: `https://token.actions.githubusercontent.com`
   - Enables OIDC authentication from GitHub Actions

3. **IAM Role**: `sipap-${var.env}-github-actions-role`
   - Trust policy allows OIDC assumption from `repo:odirasamuel/sipap-*:*`
   - Permissions for S3 and Lambda operations

## Deployment Instructions

### Step 1: Initialize and Deploy CI/CD Infrastructure

```bash
cd /dev_infra_ecs/cicd_infra

# Initialize Terraform
terraform init

# Create terraform.tfvars (optional, as defaults are set)
cat > terraform.tfvars <<EOF
github_org  = "odirasamuel"
stack_name  = "sipap"
env         = "dev"
aws_region  = "us-east-1"
additional_tags = {
  Environment = "dev"
  Project     = "sipap"
}
EOF

# Plan deployment
terraform plan -out=tfplan

# Review the plan and apply
terraform apply tfplan
```

### Step 2: Configure GitHub Repository Secrets

After successful deployment, you'll need to configure secrets in your GitHub repositories:

1. **Get the IAM Role ARN**:
   ```bash
   terraform output github_actions_role_arn
   ```

2. **Configure in GitHub**:
   - Navigate to: `https://github.com/odirasamuel/sipap-<>-mcp/settings/secrets/actions`
   - Create the following secrets/variables:
     - **Secret**: `AWS_GITHUB_ACTIONS_ROLE_ARN` = `<role-arn-from-output>`

3. **Repeat for all sipap-* repos** that need to deploy Lambdas

### Step 3: Test the Workflow

1. Push changes to the `sipap-<>-mcp` repository
2. The workflow will automatically:
   - Package the Lambda code (excluding tests, docs)
   - Upload to S3: `sipap-lambda-packages-dev/<>/lambda.zip`
   - Report the version ID

3. Verify in AWS Console:
   ```bash
   aws s3 ls s3://sipap-lambda-packages-dev/<>/
   ```

### Step 4: Deploy Lambda via Terraform

After the GitHub workflow uploads the package to S3:

```bash
cd /dev_infra_ecs/core_deploy

# Plan the update
terraform plan

# Should show Lambda function update to use S3 source
# Apply the changes
terraform apply
```

### Step 5: Verify Lambda Deployment

```bash
# Check Lambda function source
aws lambda get-function --function-name <>McpServer2 \
  --query 'Code.Location'

# Test Lambda invocation
aws lambda invoke \
  --function-name <>McpServer2 \
  --payload '{"rawPath":"/health"}' \
  --cli-binary-format raw-in-base64-out \
  response.json

# Check response
cat response.json
```

## Terraform Outputs

After deployment, the following outputs are available:

- `lambda_packages_bucket_name`: Name of the S3 bucket
- `lambda_packages_bucket_arn`: ARN of the S3 bucket
- `github_actions_role_arn`: IAM role ARN for GitHub Actions (use in secrets)
- `github_actions_role_name`: Name of the IAM role
- `oidc_provider_arn`: ARN of the GitHub OIDC provider
- `github_org_pattern`: Shows which GitHub repos can assume the role

## Adding New MCP Servers

To add a new MCP server (e.g., `sipap-deltek-mcp`):

1. **Create GitHub workflow** in the new repo (copy from sipap-<>-mcp)
2. **Configure GitHub secrets** (same as Step 2 above)
3. **Update Terraform** in `core_deploy/main.tf`:
   ```hcl
   module "new_mcp_lambda" {
     source = "../modules/lambda"

     use_s3_deployment = true
     s3_bucket         = local.lambda_packages_bucket
     s3_key            = "new-mcp-name/lambda.zip"

     # ... other configuration ...
   }
   ```
4. **Deploy**: Push to trigger workflow, then `terraform apply`

## Rollback Procedure

### Option 1: Revert to Previous S3 Version

```bash
# List versions
aws s3api list-object-versions \
  --bucket sipap-lambda-packages-dev \
  --prefix <>/lambda.zip

# Update Terraform to use specific version
# In core_deploy/main.tf, add:
s3_object_version = "PREVIOUS_VERSION_ID"

terraform apply
```

### Option 2: Revert to Local Deployment

```hcl
# In core_deploy/main.tf:
use_s3_deployment   = false
function_source_dir = "./<>McpServer"

# Ensure local copy exists, then:
terraform apply
```

## Troubleshooting

### GitHub Workflow Fails with "Access Denied"

- Verify IAM role ARN is correctly set in GitHub secrets
- Check OIDC provider trust policy includes the correct repo pattern
- Ensure S3 bucket exists and role has permissions

### Lambda Deployment Fails

- Verify S3 object exists: `aws s3 ls s3://sipap-lambda-packages-dev/<>/`
- Check Lambda execution role has permissions to read from S3
- Verify package contents are valid: `unzip -l lambda.zip`

### Terraform Shows Changes on Every Apply

- This is expected for S3-based deployments when not using version pinning
- The lifecycle rule `ignore_changes = [source_code_hash]` prevents actual updates
- To pin to a specific version, set `s3_object_version` in the module call

## Cleanup

To remove the CI/CD infrastructure:

```bash
cd /dev_infra_ecs/cicd_infra

# WARNING: This will delete the S3 bucket and all Lambda packages!
# Ensure you have backups or have reverted to local deployment first

terraform destroy
```

## Architecture Benefits

1. **Security**: OIDC eliminates long-lived credentials
2. **Automation**: Code changes automatically trigger packaging and upload
3. **Versioning**: S3 versioning enables easy rollbacks
4. **Scalability**: Single infrastructure supports all sipap-* repos
5. **Isolation**: Environment-specific buckets (dev, staging, prod)
6. **Auditability**: Git SHA embedded in S3 metadata for traceability
7. **Backward Compatibility**: Existing local deployments continue to work

## Additional Resources


