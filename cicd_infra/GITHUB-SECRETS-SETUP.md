# GitHub Secrets Configuration Guide

This guide explains how to configure GitHub repository secrets for Lambda package builds.

## Prerequisites

- AWS credentials configured for Terraform
- `cicd_infra` deployed successfully
- GitHub CLI (`gh`) installed (optional, for automated setup)

## Step 1: Get Required Values from Terraform

Navigate to the cicd_infra directory and get the Terraform outputs:

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra

# Get IAM role ARN
terraform output -raw github_actions_role_arn

# Get S3 bucket name
terraform output -raw lambda_packages_bucket_name
```

**Expected outputs:**
- IAM Role ARN: `arn:aws:iam::<account-id>:role/sipap-<env>-github-actions-role`
- S3 Bucket: `sipap-lambda-packages-<env>`

## Step 2: Configure Secrets for Each Repository

The following repositories need GitHub secrets configured:

1. **sipap-common** (layer provider)
2. **sipap-serverlesshandler-mcp** (layer provider)
3. **sipap-data-mcp** (Lambda function)
4. **sipap-intelligence-mcp** (Lambda function)

### Option A: Using GitHub CLI (Recommended)

```bash
# Set environment variables from Terraform outputs
export AWS_ROLE_ARN=$(cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra && terraform output -raw github_actions_role_arn)
export S3_BUCKET=$(cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra && terraform output -raw lambda_packages_bucket_name)

# Configure secrets for sipap-common
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-common
gh secret set AWS_GITHUB_ACTIONS_ROLE_ARN -b"$AWS_ROLE_ARN"
gh variable set S3_LAMBDA_BUCKET -b"$S3_BUCKET"

# Configure secrets for sipap-serverlesshandler-mcp
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-serverlesshandler-mcp
gh secret set AWS_GITHUB_ACTIONS_ROLE_ARN -b"$AWS_ROLE_ARN"
gh variable set S3_LAMBDA_BUCKET -b"$S3_BUCKET"

# Configure secrets for sipap-data-mcp
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-data-mcp
gh secret set AWS_GITHUB_ACTIONS_ROLE_ARN -b"$AWS_ROLE_ARN"
gh variable set S3_LAMBDA_BUCKET -b"$S3_BUCKET"

# Configure secrets for sipap-intelligence-mcp
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-intelligence-mcp
gh secret set AWS_GITHUB_ACTIONS_ROLE_ARN -b"$AWS_ROLE_ARN"
gh variable set S3_LAMBDA_BUCKET -b"$S3_BUCKET"
```

### Option B: Using GitHub Web UI

For each repository:

1. Navigate to: `https://github.com/odirasamuel/<repo-name>/settings/secrets/actions`
2. Click "New repository secret"
3. Add secret:
   - Name: `AWS_GITHUB_ACTIONS_ROLE_ARN`
   - Value: `<IAM role ARN from Step 1>`
4. Navigate to: `https://github.com/odirasamuel/<repo-name>/settings/variables/actions`
5. Click "New repository variable"
6. Add variable:
   - Name: `S3_LAMBDA_BUCKET`
   - Value: `<S3 bucket name from Step 1>`

## Step 3: Verify Configuration

After configuring secrets, verify they're accessible:

```bash
# Check secrets for a repository (won't show values, just names)
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-common
gh secret list
gh variable list

# Expected output:
# AWS_GITHUB_ACTIONS_ROLE_ARN  Updated 2024-XX-XX
# S3_LAMBDA_BUCKET             Updated 2024-XX-XX
```

## Step 4: Test Workflows

Trigger a workflow run to test the configuration:

```bash
# Test sipap-common workflow
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-common
git commit --allow-empty -m "Test Lambda package build"
git push origin main

# Monitor workflow
gh run list --workflow=build-lambda-package.yml
gh run watch  # Follow the latest run
```

**Success indicators:**
- ✅ Workflow resolves 3 Python versions (3.12, 3.13, 3.14)
- ✅ Matrix builds 3 packages successfully
- ✅ Packages uploaded to S3 bucket
- ✅ S3 object metadata includes git-sha and python-version

## Troubleshooting

### Error: "Could not assume role"

**Symptom:** Workflow fails at "Configure AWS credentials via OIDC" step

**Solution:**
1. Verify IAM role ARN is correct:
   ```bash
   cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra
   terraform output github_actions_role_arn
   ```
2. Verify the role trust policy allows the repository:
   ```bash
   aws iam get-role --role-name sipap-<env>-github-actions-role --query 'Role.AssumeRolePolicyDocument'
   ```
3. Check that the repository matches the wildcard pattern: `odirasamuel/sipap-*`

### Error: "Access Denied" when uploading to S3

**Symptom:** Workflow fails at "Upload layer to S3" step

**Solution:**
1. Verify IAM role has S3 write permissions:
   ```bash
   aws iam list-role-policies --role-name sipap-<env>-github-actions-role
   aws iam get-role-policy --role-name sipap-<env>-github-actions-role --policy-name <policy-name>
   ```
2. Verify S3 bucket exists and is accessible:
   ```bash
   aws s3 ls s3://sipap-lambda-packages-<env>/
   ```

### Error: "requirements-lambda.txt not found"

**Symptom:** Workflow fails at "Verify requirements-lambda.txt exists" step

**Solution:**
1. Verify the file exists at the repository root:
   ```bash
   cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/<repo-name>
   ls -la requirements-lambda.txt
   ```
2. If missing, create it following the pattern in sipap-common

### Workflow doesn't trigger

**Symptom:** Pushing to main doesn't trigger the workflow

**Solution:**
1. Verify the workflow file is committed:
   ```bash
   cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/<repo-name>
   git ls-files .github/workflows/build-lambda-package.yml
   ```
2. Check workflow syntax:
   ```bash
   gh workflow list
   ```
3. Check if the paths filter is preventing trigger (workflow only runs on changes to `src/**`, `pyproject.toml`, `requirements-lambda.txt`, or the workflow file itself)

## Verification Checklist

After setup, verify:

- [ ] Terraform outputs provide correct ARN and bucket name
- [ ] All 4 repositories have `AWS_GITHUB_ACTIONS_ROLE_ARN` secret configured
- [ ] All 4 repositories have `S3_LAMBDA_BUCKET` variable configured
- [ ] Test workflow runs successfully in at least one repository
- [ ] S3 bucket contains uploaded layer packages
- [ ] S3 object metadata is correctly populated

## Next Steps

Once secrets are configured and workflows are working:

1. **Proceed to Phase 5.2:** MCP Lambda Handlers
2. **Monitor costs:** Check S3 storage and data transfer costs in AWS Cost Explorer
3. **Set up alerts:** Configure CloudWatch alarms for workflow failures

## Reference

- **Plan:** `/Users/charlesotuya/.claude/plans/floofy-frolicking-blanket.md`
- **cicd_infra:** `/Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform/cicd_infra/`
- **Workflows:** `.github/workflows/build-lambda-package.yml` in each repository
- **Sentinel Pattern:** `/Users/charlesotuya/AI-Odi/sentinel/repos/sentinel-common-master/.github/workflows/`
