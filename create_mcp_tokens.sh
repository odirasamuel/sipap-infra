#!/bin/bash
set -e

echo "========================================"
echo "SIPAP MCP Token Generator"
echo "========================================"
echo ""

# Generate unique secure tokens
DATA_MCP_TOKEN=$(openssl rand -hex 32)
INTELLIGENCE_MCP_TOKEN=$(openssl rand -hex 32)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create Data MCP tokens secret
echo "1. Creating Data MCP tokens secret..."
aws secretsmanager create-secret \
  --name "/sipap/dev/data-mcp-tokens" \
  --description "Bearer tokens for SIPAP Data MCP server" \
  --secret-string "{
    \"${DATA_MCP_TOKEN}\": {
      \"owner\": \"sipap-orchestrator\",
      \"email\": \"orchestrator@sipap.internal\",
      \"roles\": [\"admin\"],
      \"groups\": [\"internal\"],
      \"policies\": [],
      \"mcp\": \"data\",
      \"created_at\": \"${TIMESTAMP}\"
    }
  }" \
  --profile odiraaws \
  --region us-east-1

DATA_MCP_ARN=$(aws secretsmanager describe-secret \
  --secret-id "/sipap/dev/data-mcp-tokens" \
  --query 'ARN' \
  --output text \
  --profile odiraaws \
  --region us-east-1)

echo "✅ Data MCP secret created"
echo ""

# Create Intelligence MCP tokens secret
echo "2. Creating Intelligence MCP tokens secret..."
aws secretsmanager create-secret \
  --name "/sipap/dev/intelligence-mcp-tokens" \
  --description "Bearer tokens for SIPAP Intelligence MCP server" \
  --secret-string "{
    \"${INTELLIGENCE_MCP_TOKEN}\": {
      \"owner\": \"sipap-orchestrator\",
      \"email\": \"orchestrator@sipap.internal\",
      \"roles\": [\"admin\"],
      \"groups\": [\"internal\"],
      \"policies\": [],
      \"mcp\": \"intelligence\",
      \"created_at\": \"${TIMESTAMP}\"
    }
  }" \
  --profile odiraaws \
  --region us-east-1

INTELLIGENCE_MCP_ARN=$(aws secretsmanager describe-secret \
  --secret-id "/sipap/dev/intelligence-mcp-tokens" \
  --query 'ARN' \
  --output text \
  --profile odiraaws \
  --region us-east-1)

echo "✅ Intelligence MCP secret created"
echo ""

# Save tokens to file (IMPORTANT: Keep secure!)
TOKENS_FILE="./mcp_tokens_$(date +%Y%m%d_%H%M%S).txt"
cat > "$TOKENS_FILE" << EOF
======================================
SIPAP MCP Tokens (KEEP SECURE!)
Generated: ${TIMESTAMP}
======================================

DATA MCP
--------
Token:      ${DATA_MCP_TOKEN}
Secret ARN: ${DATA_MCP_ARN}

INTELLIGENCE MCP
----------------
Token:      ${INTELLIGENCE_MCP_TOKEN}
Secret ARN: ${INTELLIGENCE_MCP_ARN}

======================================
TERRAFORM CONFIGURATION
======================================

Add to core_deploy/terraform.tfvars:

data_mcp_token_arn         = "${DATA_MCP_ARN}"
intelligence_mcp_token_arn = "${INTELLIGENCE_MCP_ARN}"

======================================
ORCHESTRATOR CONFIGURATION
======================================

The orchestrator will need these tokens to call the MCPs:

# Data MCP
export DATA_MCP_TOKEN="${DATA_MCP_TOKEN}"

# Intelligence MCP
export INTELLIGENCE_MCP_TOKEN="${INTELLIGENCE_MCP_TOKEN}"

Or create a secrets file:
{
  "data_mcp_token": "${DATA_MCP_TOKEN}",
  "intelligence_mcp_token": "${INTELLIGENCE_MCP_TOKEN}"
}

======================================
USAGE EXAMPLE
======================================

curl -X POST https://data-mcp-url/mcp \\
  -H "Authorization: Bearer ${DATA_MCP_TOKEN}" \\
  -H "Content-Type: application/json" \\
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

======================================
EOF

echo "========================================"
echo "✅ SUCCESS!"
echo "========================================"
echo ""
echo "Tokens saved to: $TOKENS_FILE"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "1. Store $TOKENS_FILE in a secure location (1Password, KMS, etc.)"
echo "2. DO NOT commit tokens to git"
echo "3. Add to .gitignore: mcp_tokens_*.txt"
echo "4. These tokens grant ADMIN access to all MCP tools"
echo ""
echo "Next steps:"
echo "1. Use the Secret ARNs in core_deploy/terraform.tfvars"
echo "2. Store the tokens securely for orchestrator configuration"
echo "3. Delete this file after backing up: rm $TOKENS_FILE"
echo ""
