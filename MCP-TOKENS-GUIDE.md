# SIPAP MCP Token Guide

## Overview

Each SIPAP MCP server requires bearer token authentication. This guide explains token metadata fields and how to create/manage tokens.

---

## Token Metadata Fields

### Required Fields

#### 1. **owner** (string)
- **Purpose**: Primary identifier for the token holder
- **Used for**: Audit trails, session tracking, ACL evaluation (precedence level 3)
- **Examples**:
  - `"sipap-orchestrator"` - The orchestrator service
  - `"batch-scraper"` - Batch data collection service
  - `"web-dashboard"` - Web application
  - `"whatsapp-webhook"` - WhatsApp Business API handler

#### 2. **roles** (array of strings)
- **Purpose**: Functional role-based access control (job-based permissions)
- **ACL Precedence**: Level 4 (below POLICY, above GROUP)
- **Common Values**:
  - `["admin"]` - Full access to all tools (orchestrator, internal services)
  - `["user"]` - Standard access (web apps, external APIs)
  - `["readonly"]` - Read-only access, no mutations
- **SIPAP Usage**:
  ```json
  {
    "orchestrator": ["admin"],
    "web-app": ["user"],
    "analytics": ["readonly"]
  }
  ```

#### 3. **groups** (array of strings)
- **Purpose**: Organizational grouping for resource isolation
- **ACL Precedence**: Level 5 (lowest, above DEFAULT DENY)
- **Common Values**:
  - `["internal"]` - Backend systems, trusted services
  - `["external"]` - Public APIs, webhooks
  - `["test"]` - Testing/staging environments
- **SIPAP Usage**:
  ```json
  {
    "orchestrator": ["internal"],
    "whatsapp-webhook": ["external"],
    "ci-pipeline": ["test"]
  }
  ```

### Optional Fields

#### 4. **policies** (array of strings)
- **Purpose**: Flexible policy assignment for special cases
- **ACL Precedence**: Level 2 (above OWNER, below TOKEN)
- **Common Values**:
  - `["emergency-access"]` - Temporary elevated permissions
  - `["read-only-mode"]` - Maintenance mode
  - `["beta-features"]` - Feature flag access
- **SIPAP Usage**: Currently unused (MVP), reserved for future

#### 5. **email** (string)
- **Purpose**: Contact/identification for audit logs
- **Not used in ACL**: Just for tracking and alerts
- **Examples**: `"orchestrator@sipap.internal"`, `"admin@example.com"`

#### 6. **mcp** (string)
- **Purpose**: Identifies which MCP this token belongs to
- **Values**: `"data"`, `"intelligence"`, `"weather"`, etc.
- **Useful for**: Logging, metrics, debugging

#### 7. **created_at** (ISO 8601 timestamp)
- **Purpose**: Token creation timestamp
- **Format**: `"2026-07-19T14:30:00Z"`
- **Useful for**: Audit trails, token rotation

---

## ACL Evaluation Precedence

When a token tries to access a tool, Sentinel evaluates permissions in this order:

```
1. TOKEN (specific token allow/deny)     ← Emergency revocation
   ↓
2. POLICY (assigned policies)             ← Feature flags, special access
   ↓
3. OWNER (owner-specific rules)           ← Admin overrides
   ↓
4. ROLE (functional roles)                ← Job-based permissions
   ↓
5. GROUP (organizational groups)          ← Department-based
   ↓
6. DEFAULT DENY                           ← No match = access denied
```

**First Match Wins**: Evaluation stops at the first level with matching rules.

**Example Scenarios**:

```
Scenario 1: Token Blocked
- TOKEN: DENY (priority 1000) → ❌ DENIED (stops here, other levels ignored)

Scenario 2: Role Allowed
- TOKEN: No rules
- POLICY: No rules
- OWNER: No rules
- ROLE: ALLOW (priority 100) → ✅ ALLOWED (stops here, GROUP ignored)

Scenario 3: No Match
- TOKEN: No rules
- POLICY: No rules
- OWNER: No rules
- ROLE: No rules
- GROUP: No rules
- DEFAULT: → ❌ DENIED
```

---

## SIPAP MVP Token Strategy

For the MVP, we use a **simplified approach**:

### Token Configuration

Each MCP has **one admin token** for the orchestrator:

```json
{
  "owner": "sipap-orchestrator",
  "email": "orchestrator@sipap.internal",
  "roles": ["admin"],
  "groups": ["internal"],
  "policies": [],
  "mcp": "data",
  "created_at": "2026-07-19T14:30:00Z"
}
```

### Why This Works for MVP

1. **Single Internal Consumer**: Only the orchestrator calls MCPs
2. **No Multi-Tenancy**: All requests from trusted internal system
3. **Full Access Needed**: Orchestrator needs all MCP tools
4. **Simple to Manage**: One token per MCP, easy rotation

### Future Expansion

When adding external consumers (web app, WhatsApp webhook):

```json
{
  "token_abc123": {
    "owner": "sipap-orchestrator",
    "roles": ["admin"],
    "groups": ["internal"]
  },
  "token_xyz789": {
    "owner": "web-dashboard",
    "roles": ["user"],
    "groups": ["external"]
  },
  "token_def456": {
    "owner": "whatsapp-webhook",
    "roles": ["readonly"],
    "groups": ["external"]
  }
}
```

Then configure ACL rules:

```python
# Orchestrator: Full access
acl.add_permission(ACLPermission(
    pk="ROLE#admin",
    sk="TOOL#*:*",
    effect=Effect.ALLOW
))

# External users: Limited access
acl.add_permission(ACLPermission(
    pk="GROUP#external",
    sk="TOOL#data:get_*",  # Only read operations
    effect=Effect.ALLOW
))
```

---

## Creating Tokens

### 1. Run the Token Generator Script

```bash
cd /Users/charlesotuya/AI-Odi/sentinel/sipap/repos/sipap-terraform

# Generate unique tokens for each MCP
./create_mcp_tokens.sh
```

This creates:
- `/sipap/dev/data-mcp-tokens` - Data MCP secret with unique token
- `/sipap/dev/intelligence-mcp-tokens` - Intelligence MCP secret with unique token
- `mcp_tokens_YYYYMMDD_HHMMSS.txt` - Token file (KEEP SECURE!)

### 2. Secure the Token File

The script generates a file containing:
- Raw bearer tokens (64-character hex strings)
- Secret ARNs for Terraform
- Usage examples

**CRITICAL SECURITY STEPS:**

```bash
# 1. Store in password manager (1Password, LastPass, etc.)
#    OR encrypt and store in KMS
aws kms encrypt \
  --key-id alias/sipap-tokens \
  --plaintext fileb://mcp_tokens_*.txt \
  --output text \
  --query CiphertextBlob \
  --profile odiraaws > tokens.encrypted

# 2. Delete the plaintext file
rm mcp_tokens_*.txt

# 3. Add to .gitignore (already done)
echo "mcp_tokens_*.txt" >> .gitignore
```

### 3. Configure Terraform

Copy the Secret ARNs into `core_deploy/terraform.tfvars`:

```hcl
data_mcp_token_arn         = "arn:aws:secretsmanager:us-east-1:810278669998:secret:/sipap/dev/data-mcp-tokens-abc123"
intelligence_mcp_token_arn = "arn:aws:secretsmanager:us-east-1:810278669998:secret:/sipap/dev/intelligence-mcp-tokens-xyz789"
```

### 4. Configure Orchestrator

The orchestrator needs the raw tokens to call MCPs:

```python
# Option 1: Environment variables
export DATA_MCP_TOKEN="abc123..."
export INTELLIGENCE_MCP_TOKEN="xyz789..."

# Option 2: Store in Secrets Manager (recommended)
aws secretsmanager create-secret \
  --name "/sipap/dev/orchestrator-mcp-tokens" \
  --secret-string '{
    "data_mcp": "abc123...",
    "intelligence_mcp": "xyz789..."
  }' \
  --profile odiraaws

# Orchestrator code
import boto3
import json

sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='/sipap/dev/orchestrator-mcp-tokens')
tokens = json.loads(secret['SecretString'])

# Call Data MCP
headers = {'Authorization': f'Bearer {tokens["data_mcp"]}'}
response = requests.post(data_mcp_url, headers=headers, json=mcp_request)
```

---

## Token Rotation

To rotate tokens (recommended every 90 days):

### 1. Add New Token to Secret

```bash
# Get current tokens
CURRENT=$(aws secretsmanager get-secret-value \
  --secret-id "/sipap/dev/data-mcp-tokens" \
  --query SecretString \
  --output text \
  --profile odiraaws)

# Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# Add to existing secret (preserves old token during migration)
echo $CURRENT | jq ". + {\"$NEW_TOKEN\": {\"owner\": \"sipap-orchestrator\", \"roles\": [\"admin\"], \"groups\": [\"internal\"]}}" > new_tokens.json

aws secretsmanager update-secret \
  --secret-id "/sipap/dev/data-mcp-tokens" \
  --secret-string file://new_tokens.json \
  --profile odiraaws
```

### 2. Update Orchestrator

Deploy orchestrator with new token.

### 3. Remove Old Token

Once confirmed working:

```bash
# Remove old token from secret
echo $CURRENT | jq "del(.\"OLD_TOKEN_HERE\")" > updated_tokens.json

aws secretsmanager update-secret \
  --secret-id "/sipap/dev/data-mcp-tokens" \
  --secret-string file://updated_tokens.json \
  --profile odiraaws
```

---

## Troubleshooting

### Token Rejected (401 Unauthorized)

1. **Check token is in secret**:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id "/sipap/dev/data-mcp-tokens" \
     --query SecretString \
     --output text \
     --profile odiraaws | jq .
   ```

2. **Verify Authorization header format**:
   ```
   Authorization: Bearer abc123...
   ```
   Not: `Token abc123...` or `abc123...` (missing "Bearer ")

3. **Check Lambda environment variable**:
   ```bash
   aws lambda get-function-configuration \
     --function-name SipapDataMcpServer \
     --query 'Environment.Variables.MCP_TOKEN_ARN' \
     --profile odiraaws
   ```

### Access Denied to Tool

1. **Check ACL rules** (if configured):
   ```python
   # In MCP server code
   acl.list_permissions(pk=f"ROLE#{role}")
   ```

2. **Verify token metadata**:
   - Does token have `"roles": ["admin"]`?
   - Is `owner` set correctly?

3. **Check ACL mode**:
   - In dev: Use `permissive` mode (logs denials, allows anyway)
   - In prod: Use `enforce` mode (blocks denials)

---

## Security Best Practices

1. **Never commit tokens to git** (.gitignore already configured)
2. **Use unique tokens per MCP** (script generates this by default)
3. **Rotate tokens every 90 days**
4. **Store tokens in Secrets Manager** (not environment variables in code)
5. **Use AWS IAM for orchestrator** (EC2 instance profile, ECS task role)
6. **Enable CloudWatch logging** for token usage audit
7. **Monitor failed auth attempts** (set up CloudWatch alarms)

---

## References

- [Sentinel ACL Documentation](../../../sentinel-serverlesshandler-mcp-main/docs/ACL.md)
- [Sentinel Session Architecture](../../../sentinel-serverlesshandler-mcp-main/docs/SESSION.md)
- [Sentinel Token Providers](../../../sentinel-serverlesshandler-mcp-main/docs/ZONE.md)
