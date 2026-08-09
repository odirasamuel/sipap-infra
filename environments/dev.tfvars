# SIPAP Development Environment Configuration

env        = "dev"
stack_name = "sipap"
aws_region = "us-east-1"

# VPC Configuration
# Using 172.31.0.0/16 - AWS default VPC range (we're replacing it with our infrastructure)
vpc_cidr             = "172.31.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
private_subnet_cidrs = ["172.31.11.0/24", "172.31.12.0/24", "172.31.13.0/24"]

# NAT Gateway Configuration (1 for cost optimization, 3 for high availability)
nat_gateway_count = 1

# Database Configuration (Mode: Standard RDS for cost optimization)
aurora_use_serverless  = false  # false = Standard RDS (cost-optimized), true = Aurora Serverless v2
aurora_instance_class  = "db.t4g.micro"  # ~$12/mo vs Aurora Serverless ~$43-87/mo
database_name          = "sipap_dev"
db_master_username     = "sipap_admin"

# Cache Configuration (Mode: Standard Instance for cost optimization)
elasticache_use_serverless = false  # false = Standard Instance (cost-optimized), true = Serverless
elasticache_node_type      = "cache.t4g.micro"  # ~$13/mo vs Serverless ~$24/mo

data_mcp_token_arn         = "arn:aws:secretsmanager:us-east-1:810278669998:secret:/sipap/dev/data-mcp-tokens-5rg9Q5"
intelligence_mcp_token_arn = "arn:aws:secretsmanager:us-east-1:810278669998:secret:/sipap/dev/intelligence-mcp-tokens-bdKsAA"

# Database and cache endpoints (from parent terraform output)
redis_endpoint           = "sipap-dev-redis.qnk6bl.0001.use1.cache.amazonaws.com"
postgres_host            = "sipap-dev-rds.c2hooq6iskvw.us-east-1.rds.amazonaws.com"
postgres_db              = "sipap_dev"
postgres_credentials_arn = "arn:aws:secretsmanager:us-east-1:810278669998:secret:sipap/dev/aurora-credentials-j0j6ay"

# Additional Tags
additional_tags = {
  CostCenter = "Development"
  # Owner      = "charles@sipap.com"
}

# ECS Services Configuration
# NOTE: ECR image URL is constructed automatically in main.tf using module.ecr.repository_urls["orchestrator"]
# NOTE: Task role ARN and security group ID are pulled from core_deploy remote state
ecs_services = [
  {
    name          = "orchestrator-service"
    image         = "810278669998.dkr.ecr.us-east-1.amazonaws.com/sipap-dev-orchestrator:latest"
    cpu           = 1024  # 1 vCPU
    memory        = 2048  # 2 GB RAM
    desired_count = 1     # Start with 1 task, scale later

    port_mappings = [
      {
        container_port = 8080
        protocol       = "tcp"
      }
    ]

    environment_variables = [
      { name = "ENVIRONMENT", value = "dev" },
      { name = "SERVICE_NAME", value = "orchestrator-service" },
      { name = "LOG_LEVEL", value = "INFO" },
      { name = "MODEL_ID", value = "anthropic.claude-sonnet-4-5-20250929-v1" },
      { name = "REDIS_SSL", value = "true" },
      { name = "ENABLE_WHATSAPP_DELIVERY", value = "false" },
      # These will be interpolated in main.tf from remote state/outputs:
      # DATA_MCP_URL, INTELLIGENCE_MCP_URL, BEDROCK_PROFILE_ARN,
      # REDIS_ENDPOINT, SQS_QUEUE_URL, POSTGRES_HOST, POSTGRES_DB
    ]

    secrets = [
      # Aurora credentials from Secrets Manager
      # Format: { name = "ENV_VAR_NAME", value_from = "arn:aws:secretsmanager:..." }
    ]

    health_check = {
      # Sentinel pattern: Check heartbeat file age (daemon mode)
      # Heartbeat file is updated every ~20s during SQS polling (before each SQS long poll)
      # If file age > 30s, daemon is stuck
      command      = ["CMD-SHELL", "test -f /tmp/sipap-heartbeat || exit 1; LAST_UPDATED=$(jq -r .timestamp /tmp/sipap-heartbeat) && CURRENT_TIME=$(date +%s) && HEARTBEAT_AGE=$((CURRENT_TIME - $${LAST_UPDATED%.*})) && test $HEARTBEAT_AGE -le 30"]
      interval     = 5   # Check every 5 seconds (Sentinel pattern)
      timeout      = 2   # 2 seconds per check
      retries      = 3   # Kill after 3 consecutive failures
      start_period = 10  # 10 seconds grace period on startup
    }

    deployment_configuration = {
      maximum_percent         = 200
      minimum_healthy_percent = 100
    }

    enable_deployment_circuit_breaker = true
    enable_deployment_rollback        = true
    force_new_deployment              = true  # Force deployment on every apply (triggers on image changes)
  }
]
