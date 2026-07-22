#!/usr/bin/env bash
# Configure GitHub secrets for Lambda package builds
# This script automates the setup process described in GITHUB-SECRETS-SETUP.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CICD_INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SIPAP_REPOS_DIR="$(dirname "$(dirname "$CICD_INFRA_DIR")")"

echo "=== SIPAP GitHub Secrets Configuration ==="
echo "Script directory: ${SCRIPT_DIR}"
echo "cicd_infra directory: ${CICD_INFRA_DIR}"
echo "SIPAP repos directory: ${SIPAP_REPOS_DIR}"
echo ""

# Step 1: Get Terraform outputs
echo "Step 1: Extracting Terraform outputs..."
cd "${CICD_INFRA_DIR}"

if [[ ! -f terraform.tfstate ]]; then
  echo "❌ ERROR: terraform.tfstate not found"
  echo "   Please run 'terraform apply' in cicd_infra first"
  exit 1
fi

AWS_ROLE_ARN=$(terraform output -raw github_actions_role_arn 2>/dev/null)
S3_BUCKET=$(terraform output -raw lambda_packages_bucket_name 2>/dev/null)

if [[ -z "$AWS_ROLE_ARN" || -z "$S3_BUCKET" ]]; then
  echo "❌ ERROR: Failed to extract Terraform outputs"
  echo "   AWS_ROLE_ARN: ${AWS_ROLE_ARN:-<empty>}"
  echo "   S3_BUCKET: ${S3_BUCKET:-<empty>}"
  exit 1
fi

echo "✅ Extracted Terraform outputs:"
echo "   AWS_ROLE_ARN: ${AWS_ROLE_ARN}"
echo "   S3_BUCKET: ${S3_BUCKET}"
echo ""

# Step 2: Check GitHub CLI is installed
echo "Step 2: Checking GitHub CLI availability..."
if ! command -v gh &> /dev/null; then
  echo "❌ ERROR: GitHub CLI (gh) is not installed"
  echo "   Install: brew install gh  (macOS)"
  echo "   Or follow: https://cli.github.com/manual/installation"
  exit 1
fi

echo "✅ GitHub CLI found: $(gh --version | head -1)"
echo ""

# Step 3: Check GitHub authentication
echo "Step 3: Verifying GitHub authentication..."
if ! gh auth status &> /dev/null; then
  echo "❌ ERROR: Not authenticated with GitHub"
  echo "   Run: gh auth login"
  exit 1
fi

echo "✅ Authenticated with GitHub"
echo ""

# Step 4: Configure secrets for each repository
REPOS=(
  "sipap-common"
  "sipap-serverlesshandler-mcp"
  "sipap-data-mcp"
  "sipap-intelligence-mcp"
)

echo "Step 4: Configuring secrets for ${#REPOS[@]} repositories..."
echo ""

for REPO in "${REPOS[@]}"; do
  REPO_DIR="${SIPAP_REPOS_DIR}/${REPO}"

  echo "Configuring: ${REPO}"

  # Check if repository directory exists
  if [[ ! -d "$REPO_DIR" ]]; then
    echo "⚠️  WARNING: Directory not found: ${REPO_DIR}"
    echo "   Skipping ${REPO}"
    continue
  fi

  # Check if it's a git repository
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    echo "⚠️  WARNING: Not a git repository: ${REPO_DIR}"
    echo "   Skipping ${REPO}"
    continue
  fi

  cd "${REPO_DIR}"

  # Set secret: AWS_GITHUB_ACTIONS_ROLE_ARN
  echo "  Setting secret: AWS_GITHUB_ACTIONS_ROLE_ARN..."
  if gh secret set AWS_GITHUB_ACTIONS_ROLE_ARN -b"${AWS_ROLE_ARN}" 2>&1; then
    echo "  ✅ Secret set successfully"
  else
    echo "  ❌ Failed to set secret"
    echo "     This may be due to insufficient permissions"
    echo "     Continuing with next repository..."
  fi

  # Set variable: S3_LAMBDA_BUCKET
  echo "  Setting variable: S3_LAMBDA_BUCKET..."
  if gh variable set S3_LAMBDA_BUCKET -b"${S3_BUCKET}" 2>&1; then
    echo "  ✅ Variable set successfully"
  else
    echo "  ❌ Failed to set variable"
    echo "     This may be due to insufficient permissions"
    echo "     Continuing with next repository..."
  fi

  echo "  ✅ Completed: ${REPO}"
  echo ""
done

# Step 5: Verify configuration
echo "Step 5: Verifying configuration..."
echo ""

ALL_SUCCESS=true

for REPO in "${REPOS[@]}"; do
  REPO_DIR="${SIPAP_REPOS_DIR}/${REPO}"

  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    continue
  fi

  cd "${REPO_DIR}"

  echo "Checking: ${REPO}"

  # List secrets (won't show values, just names)
  if gh secret list | grep -q "AWS_GITHUB_ACTIONS_ROLE_ARN"; then
    echo "  ✅ Secret: AWS_GITHUB_ACTIONS_ROLE_ARN"
  else
    echo "  ❌ Secret missing: AWS_GITHUB_ACTIONS_ROLE_ARN"
    ALL_SUCCESS=false
  fi

  # List variables
  if gh variable list | grep -q "S3_LAMBDA_BUCKET"; then
    echo "  ✅ Variable: S3_LAMBDA_BUCKET"
  else
    echo "  ❌ Variable missing: S3_LAMBDA_BUCKET"
    ALL_SUCCESS=false
  fi

  echo ""
done

# Summary
echo "=== Configuration Summary ==="
if $ALL_SUCCESS; then
  echo "✅ All repositories configured successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Test workflows by pushing to main in any repository"
  echo "  2. Monitor workflow runs: gh run list --workflow=build-lambda-package.yml"
  echo "  3. Verify S3 uploads: aws s3 ls s3://${S3_BUCKET}/"
  echo ""
  echo "See GITHUB-SECRETS-SETUP.md for more details"
else
  echo "⚠️  Some repositories failed configuration"
  echo "   Check the output above for details"
  echo "   You may need to configure manually via GitHub web UI"
  echo ""
  echo "See GITHUB-SECRETS-SETUP.md for manual setup instructions"
  exit 1
fi
