# SIPAP Core Deployment - Lambda MCPs + ECS Orchestrator

# ==============================================================================
# S3 DATA SOURCES - Track Lambda packages for automatic updates
# ==============================================================================

# Shared MCP Handler Layer (sipap-serverlesshandler-mcp)
data "aws_s3_object" "serverless_mcp_handler" {
  bucket = "sipap-lambda-packages-dev"
  key    = "serverlesshandler-mcp/python_3.13/layer.zip"
}

# Common Layer (sipap-common)
data "aws_s3_object" "common_layer" {
  bucket = "sipap-lambda-packages-dev"
  key    = "common/python_3.13/layer.zip"
}

# Data MCP Dependency Layer
data "aws_s3_object" "data_mcp_layer" {
  bucket = "sipap-lambda-packages-dev"
  key    = "data-mcp/python_3.13/layer.zip"
}

# Data MCP Function Code
data "aws_s3_object" "data_mcp_function" {
  bucket = "sipap-lambda-packages-dev"
  key    = "data-mcp/python_3.13/data_mcp_lambda_package.zip"
}

# Intelligence MCP Dependency Layer
data "aws_s3_object" "intelligence_mcp_layer" {
  bucket = "sipap-lambda-packages-dev"
  key    = "intelligence-mcp/python_3.13/layer.zip"
}

# Intelligence MCP Function Code
data "aws_s3_object" "intelligence_mcp_function" {
  bucket = "sipap-lambda-packages-dev"
  key    = "intelligence-mcp/python_3.13/intelligence_mcp_lambda_package.zip"
}

# WhatsApp Auth Handler Function Code
data "aws_s3_object" "whatsapp_auth_function" {
  bucket = "sipap-lambda-packages-dev"
  key    = "auth-handlers/python_3.13/whatsapp_auth_handler.zip"
}

# Payment Webhook Handler Function Code
data "aws_s3_object" "payment_webhook_function" {
  bucket = "sipap-lambda-packages-dev"
  key    = "auth-handlers/python_3.13/payment_webhook_handler.zip"
}

# Payment Session Handler Function Code
data "aws_s3_object" "payment_session_function" {
  bucket = "sipap-lambda-packages-dev"
  key    = "auth-handlers/python_3.13/payment_session_handler.zip"
}

# API Keys Secret (contains API_FOOTBALL_KEY)
data "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = data.terraform_remote_state.base.outputs.api_keys_secret_arn
}

# ==============================================================================
# REMOTE STATE - Reference parent module's outputs
# ==============================================================================

data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket  = "sipap-dev-tf-state-bucket"
    key     = "sipap-dev-root-tf-state"
    region  = "us-west-1"
    profile = "odiraaws"
  }
}

# ==============================================================================
# DATA SOURCES - Account information
# ==============================================================================

data "aws_caller_identity" "current" {
}

# ==============================================================================
# LOCAL VARIABLES - Policy resolution and dynamic configuration
# ==============================================================================

locals {
  # S3 bucket for Lambda packages
  lambda_packages_bucket = "sipap-lambda-packages-dev"

  # Account ID for policy templates
  account_id = data.aws_caller_identity.current.account_id

  # Infrastructure values from parent module (via remote state)
  vpc_id                   = data.terraform_remote_state.base.outputs.vpc_id
  private_subnet_ids       = data.terraform_remote_state.base.outputs.private_subnet_ids
  redis_endpoint           = data.terraform_remote_state.base.outputs.elasticache_configuration_endpoint
  postgres_host            = data.terraform_remote_state.base.outputs.aurora_cluster_endpoint
  postgres_db              = data.terraform_remote_state.base.outputs.aurora_database_name
  postgres_credentials_arn = data.terraform_remote_state.base.outputs.aurora_credentials_secret_arn
  api_keys_secret_arn      = data.terraform_remote_state.base.outputs.api_keys_secret_arn

  # Policy file hashes for change tracking
  policy_file_hashes = {
    mcp_servers_policy = fileexists("${path.module}/../modules/policies/mcp_servers_policy.json") ? filesha256("${path.module}/../modules/policies/mcp_servers_policy.json") : "not-created-yet"
  }

  # Common layer is built but not yet used (will attach sipap-common layer separately)
  # Following Sentinel pattern: attach common layer to all MCP functions
}

# ==============================================================================
# BEDROCK INFERENCE PROFILES - Claude Sonnet 4.5 for AI reasoning
# ==============================================================================

# Bedrock Inference Profile for SIPAP Orchestrator
# Used by orchestrator agents (Routing, Planner, Analyzer) for AI-powered sports intelligence
resource "aws_bedrock_inference_profile" "orchestrator" {
  name        = "${var.stack_name}-${var.env}-orchestrator-profile"
  description = "SIPAP orchestrator profile for AI sports intelligence"

  model_source {
    copy_from = "arn:aws:bedrock:us-east-1::inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0"
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-orchestrator-profile"
      Environment = var.env
      Platform    = "ECS-Fargate"
      Service     = "orchestrator-service"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Bedrock Inference Profile for SIPAP Intelligence MCP
# Used by intelligence-mcp for news sentiment analysis, weather impact assessment, injury report interpretation
resource "aws_bedrock_inference_profile" "intelligence_mcp" {
  name        = "${var.stack_name}-${var.env}-intelligence-mcp-profile"
  description = "SIPAP Intelligence MCP profile for AI news weather analysis"

  model_source {
    copy_from = "arn:aws:bedrock:us-east-1::inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0"
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-intelligence-mcp-profile"
      Environment = var.env
      Service     = "intelligence-mcp"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# API GATEWAY CLOUDWATCH LOGS ROLE - Account-level configuration
# ==============================================================================

# IAM role for API Gateway to write logs to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.stack_name}-${var.env}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-api-gateway-cloudwatch-role"
      Environment = var.env
      Purpose     = "API Gateway CloudWatch Logs"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Attach AWS managed policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Set the CloudWatch role at the account level (required for access logs)
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

# ==============================================================================
# WHATSAPP SQS QUEUE - Asynchronous message processing
# ==============================================================================

module "whatsapp_sqs" {
  source = "../modules/whatsapp_sqs"

  stack_name = var.stack_name
  env        = var.env

  # Queue configuration
  # 2026-08-22: Increased from 60s to 900s (15 minutes) for batch predictions
  # Batch predictions process 100 fixtures × 44 markets and take 5-10+ minutes
  # VisibilityTimeoutExtender extends every 60s, but needs base timeout to be long enough
  visibility_timeout_seconds     = 900     # 15 minutes (batch predictions take 5-10+ minutes)
  dlq_visibility_timeout_seconds = 60      # 1 minute for DLQ
  max_message_size               = 262144  # 256 KB
  message_retention_seconds      = 1209600 # 14 days
  receive_wait_time_seconds      = 20      # Long polling (reduces API calls by ~95%)
  max_receive_count              = 30      # 30 retries before DLQ

  additional_tags = var.additional_tags
}

# ==============================================================================
# WHATSAPP API GATEWAY - Webhook → SQS integration
# ==============================================================================

module "whatsapp_api_gateway" {
  source = "../modules/whatsapp_api_gateway"

  stack_name = var.stack_name
  env        = var.env

  # SQS integration (still needed for Lambda to forward authenticated messages)
  sqs_queue_url = module.whatsapp_sqs.queue_url
  sqs_queue_arn = module.whatsapp_sqs.queue_arn

  # Lambda integration for authentication
  # When enabled, API Gateway routes to Lambda first, which checks subscription status
  # and either forwards to SQS (active users) or returns signup/renewal links (new/expired users)
  use_lambda_integration = var.enable_whatsapp_auth
  lambda_invoke_arn      = var.enable_whatsapp_auth ? module.whatsapp_auth_lambda.invoke_arn : ""
  lambda_function_name   = var.enable_whatsapp_auth ? module.whatsapp_auth_lambda.function_name : ""

  # Observability
  enable_xray_tracing = true
  log_retention_days  = 90

  # Rate limiting and quota
  throttle_rate_limit  = 50    # 50 requests per second
  throttle_burst_limit = 20    # 20 concurrent requests
  quota_limit          = 10000 # 10,000 requests per day
  quota_period         = "DAY"

  additional_tags = var.additional_tags

  depends_on = [
    module.whatsapp_sqs,
    aws_api_gateway_account.main
    # Note: module.whatsapp_auth_lambda removed to break circular dependency
    # Implicit dependency exists via lambda_invoke_arn and lambda_function_name references
  ]
}

# ==============================================================================
# IAM ROLE FOR MCP SERVERS
# ==============================================================================

module "mcp_servers_role" {
  source = "../modules/role"

  role_description = "IAM execution role for SIPAP MCP Lambda servers"
  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "mcp-servers"

  # Lambda service can assume this role
  assume_role_policy = templatefile("${path.module}/../modules/assume_role_policies/lambda_assume_role.json", {})

  # Inline policies for MCP servers
  inline_policies = [
    {
      name = "mcp-servers-policy"
      policy = templatefile("${path.module}/../modules/policies/mcp_servers_policy.json", {
        account_id = local.account_id
      })
    },
    {
      name = "bedrock-access-policy"
      policy = templatefile("${path.module}/../modules/policies/bedrock_access_policy.json", {
        inference_profile_arn = aws_bedrock_inference_profile.intelligence_mcp.arn
        account_id            = local.account_id
      })
    }
  ]

  # AWS managed policies
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  additional_tags = var.additional_tags

}

# ==============================================================================
# SECURITY GROUP FOR LAMBDA INTERNAL FUNCTIONS
# ==============================================================================

module "lambda_internal_security_group" {
  source = "../modules/security_groups"

  stack_name = var.stack_name
  env        = var.env
  vpc_id     = local.vpc_id
  aws_region = var.aws_region
  stack_tool = "lambda-mcp-internal"

  # No inbound rules (internal only, accessed via Function URLs)
  ingress_rules = []

  # Allow all outbound traffic (RDS, ElastiCache, external APIs)
  egress_rules = [
    {
      description      = "Allow all outbound traffic"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    }
  ]

  additional_tags = merge(var.additional_tags, {
    Purpose = "lambda-mcp-internal"
  })

}

# ==============================================================================
# SHARED MCP HANDLER LAYER - Reused by all MCP servers
# ==============================================================================

module "shared_mcp_handler_layer" {
  source = "../modules/lambda_layers"

  # S3-based deployment (packages already uploaded)
  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket

  # Create only the MCP handler layer
  create_mcp_handler_layer  = true
  create_dependencies_layer = false

  # Handler layer configuration
  mcp_handler_s3_key      = "serverlesshandler-mcp/python_3.13/layer.zip"
  mcp_handler_s3_version  = data.aws_s3_object.serverless_mcp_handler.version_id
  mcp_handler_source_dir  = "" # Using S3, not local source
  mcp_handler_layer_name  = "SipapServerlessMcpHandler"
  mcp_handler_description = "Shared MCP Server Engine for SIPAP MCP servers (sipap_mcp package)"

  # Python runtime compatibility
  compatible_runtimes      = ["python3.12", "python3.13"]
  compatible_architectures = ["x86_64"]

  # Tags with ETag tracking for updates
  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.serverless_mcp_handler.etag
    LayerType   = "shared-handler"
  })

}

# ==============================================================================
# COMMON LAYER - sipap-common package (shared utilities)
# ==============================================================================

module "common_layer" {
  source = "../modules/lambda_layers"

  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket

  create_mcp_handler_layer  = false
  create_dependencies_layer = true

  dependencies_s3_key      = "common/python_3.13/layer.zip"
  dependencies_s3_version  = data.aws_s3_object.common_layer.version_id
  dependencies_layer_name  = "SipapCommonLayer"
  dependencies_description = "SIPAP common utilities (sipap_common package)"

  compatible_runtimes      = ["python3.12", "python3.13"]
  compatible_architectures = ["x86_64"]

  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.common_layer.etag
    LayerType   = "common-utilities"
  })

}

# ==============================================================================
# DATA MCP DEPENDENCY LAYER
# ==============================================================================
# NOTE (2026-08-20): Database removed. Layer now contains aiohttp for API-Football
# instead of asyncpg. Description kept unchanged to avoid layer replacement.

module "data_mcp_lambda_layers" {
  source = "../modules/lambda_layers"

  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket

  create_mcp_handler_layer  = false
  create_dependencies_layer = true

  dependencies_s3_key      = "data-mcp/python_3.13/layer.zip"
  dependencies_s3_version  = data.aws_s3_object.data_mcp_layer.version_id
  dependencies_layer_name  = "SipapDataMcpDependencies"
  dependencies_description = "Dependencies for SIPAP Data MCP (asyncpg for async PostgreSQL)"

  compatible_runtimes      = ["python3.12", "python3.13"]
  compatible_architectures = ["x86_64"]

  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.data_mcp_layer.etag
    MCPType     = "data"
  })

}

# ==============================================================================
# INTELLIGENCE MCP DEPENDENCY LAYER - httpx for HTTP requests
# ==============================================================================

module "intelligence_mcp_lambda_layers" {
  source = "../modules/lambda_layers"

  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket

  create_mcp_handler_layer  = false
  create_dependencies_layer = true

  dependencies_s3_key      = "intelligence-mcp/python_3.13/layer.zip"
  dependencies_s3_version  = data.aws_s3_object.intelligence_mcp_layer.version_id
  dependencies_layer_name  = "SipapIntelligenceMcpDependencies"
  dependencies_description = "Dependencies for SIPAP Intelligence MCP (httpx for API calls)"

  compatible_runtimes      = ["python3.12", "python3.13"]
  compatible_architectures = ["x86_64"]

  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.intelligence_mcp_layer.etag
    MCPType     = "intelligence"
  })

}

# ==============================================================================
# DATA MCP LAMBDA FUNCTION
# ==============================================================================

module "data_mcp_lambda_internal" {
  source = "../modules/lambda"

  internal_function_name = "SipapDataMcpServer"
  external_function_name = "SipapDataMcpServer"

  # S3-based deployment configuration
  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket
  s3_key            = "data-mcp/python_3.13/data_mcp_lambda_package.zip"
  s3_object_version = data.aws_s3_object.data_mcp_function.version_id

  # Layer attachment (3 layers: common + serverlesshandler + data-mcp dependencies)
  mcp_handler_layer_arn          = module.shared_mcp_handler_layer.mcp_handler_layer_arn
  dependencies_layer_arn         = module.data_mcp_lambda_layers.dependencies_layer_arn
  additional_internal_layer_arns = [module.common_layer.dependencies_layer_arn]

  lambda_execution_role_arn = module.mcp_servers_role.role_arn
  mcp_token_arn             = var.data_mcp_token_arn

  create_internal_function = true
  create_external_function = false

  # VPC Configuration
  private_subnet_ids = local.private_subnet_ids
  security_group_ids = [module.lambda_internal_security_group.security_group_id]

  # Runtime Configuration
  lambda_runtime                = "python3.13"
  lambda_architectures          = ["x86_64"]
  lambda_handler                = "sipap_data_mcp.lambda_handler.handler"
  lambda_timeout                = 180
  lambda_memory_size            = 512
  lambda_ephemeral_storage_size = 1024

  # Environment Variables
  # Database removed (2026-08-20) - Data MCP now uses API-Football directly
  internal_lambda_environment_variables = {
    REDIS_ENDPOINT   = local.redis_endpoint
    REDIS_SSL        = "false"
    LOG_LEVEL        = "INFO"
    # API-Football key (required - Data MCP v3.0)
    API_FOOTBALL_KEY = jsondecode(data.aws_secretsmanager_secret_version.api_keys.secret_string)["API_FOOTBALL_KEY"]
  }

  internal_lambda_description = "SIPAP Data MCP Server - Sports data, fixtures, standings (v3.0 API-Football only)"

  # Lambda Function URL Configuration
  enable_function_url                    = true
  function_url_auth_type                 = "AWS_IAM"
  enable_orchestrator_invoke_permissions = true
  orchestrator_task_role_arn             = module.orchestrator_task_role.role_arn

  # SSM Parameter Store Configuration
  create_ssm_parameter   = true
  ssm_service_identifier = "data-mcp"
  ssm_mcp_timeout        = 300

  # CORS Configuration
  function_url_cors = {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 3600
  }

  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.data_mcp_function.etag
    MCPType     = "data"
  })


  depends_on = [
    module.shared_mcp_handler_layer,
    module.common_layer,
    module.data_mcp_lambda_layers,
    module.mcp_servers_role,
    module.lambda_internal_security_group
  ]
}

# ==============================================================================
# INTELLIGENCE MCP LAMBDA FUNCTION
# ==============================================================================

module "intelligence_mcp_lambda_internal" {
  source = "../modules/lambda"

  internal_function_name = "SipapIntelligenceMcpServer"
  external_function_name = "SipapIntelligenceMcpServer"

  # S3-based deployment configuration
  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket
  s3_key            = "intelligence-mcp/python_3.13/intelligence_mcp_lambda_package.zip"
  s3_object_version = data.aws_s3_object.intelligence_mcp_function.version_id

  # Layer attachment (3 layers: common + serverlesshandler + intelligence-mcp dependencies)
  mcp_handler_layer_arn          = module.shared_mcp_handler_layer.mcp_handler_layer_arn
  dependencies_layer_arn         = module.intelligence_mcp_lambda_layers.dependencies_layer_arn
  additional_internal_layer_arns = [module.common_layer.dependencies_layer_arn]

  lambda_execution_role_arn = module.mcp_servers_role.role_arn
  mcp_token_arn             = var.intelligence_mcp_token_arn

  create_internal_function = true
  create_external_function = false

  # VPC Configuration
  private_subnet_ids = local.private_subnet_ids
  security_group_ids = [module.lambda_internal_security_group.security_group_id]

  # Runtime Configuration
  lambda_runtime                = "python3.13"
  lambda_architectures          = ["x86_64"]
  lambda_handler                = "sipap_intelligence_mcp.lambda_handler.handler"
  lambda_timeout                = 180
  lambda_memory_size            = 512
  lambda_ephemeral_storage_size = 1024

  # Environment Variables
  internal_lambda_environment_variables = {
    REDIS_ENDPOINT      = local.redis_endpoint
    REDIS_SSL           = "false"
    LOG_LEVEL           = "INFO"
    BEDROCK_MODEL_ID    = "anthropic.claude-sonnet-4-5-20250929-v1"
    BEDROCK_PROFILE_ARN = aws_bedrock_inference_profile.intelligence_mcp.arn
    API_KEYS_SECRET_ARN = local.api_keys_secret_arn
  }

  internal_lambda_description = "SIPAP Intelligence MCP Server - News aggregation and sentiment analysis"

  # Lambda Function URL Configuration
  enable_function_url                    = true
  function_url_auth_type                 = "AWS_IAM"
  enable_orchestrator_invoke_permissions = true
  orchestrator_task_role_arn             = module.orchestrator_task_role.role_arn

  # SSM Parameter Store Configuration
  create_ssm_parameter   = true
  ssm_service_identifier = "intelligence-mcp"
  ssm_mcp_timeout        = 300

  # CORS Configuration
  function_url_cors = {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 3600
  }

  additional_tags = merge(var.additional_tags, {
    PackageETag = data.aws_s3_object.intelligence_mcp_function.etag
    MCPType     = "intelligence"
  })


  depends_on = [
    module.shared_mcp_handler_layer,
    module.common_layer,
    module.intelligence_mcp_lambda_layers,
    module.mcp_servers_role,
    module.lambda_internal_security_group
  ]
}

# ==============================================================================
# ORCHESTRATOR TASK ROLE - IAM role for ECS orchestrator service
# ==============================================================================

module "orchestrator_task_role" {
  source = "../modules/role"

  role_description   = "IAM task role for SIPAP orchestrator ECS service"
  stack_name         = var.stack_name
  env                = var.env
  aws_region         = var.aws_region
  stack_tool         = "orchestrator"
  assume_role_policy = templatefile("${path.module}/../modules/assume_role_policies/ecs_assume_role.json", {})

  # Inline policies for orchestrator
  inline_policies = [
    {
      name = "bedrock-inference-access"
      policy = templatefile("${path.module}/../modules/policies/bedrock_access_policy.json", {
        inference_profile_arn = aws_bedrock_inference_profile.orchestrator.arn
        account_id            = local.account_id
      })
    },
    {
      name = "lambda-mcp-invoke"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "lambda:InvokeFunction",
              "lambda:InvokeFunctionUrl"
            ]
            Resource = [
              module.data_mcp_lambda_internal.internal_function_arn,
              module.intelligence_mcp_lambda_internal.internal_function_arn
            ]
          }
        ]
      })
    },
    {
      name = "sqs-whatsapp-queue-access"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "sqs:ReceiveMessage",
              "sqs:DeleteMessage",
              "sqs:GetQueueAttributes",
              "sqs:ChangeMessageVisibility",
              "sqs:GetQueueUrl"
            ]
            Resource = module.whatsapp_sqs.queue_arn
          }
        ]
      })
    },
    {
      name = "secrets-manager-access"
      policy = templatefile("${path.module}/../modules/policies/secrets_manager_policy.json", {
        aurora_credentials_secret_arn = local.postgres_credentials_arn
        api_keys_secret_arn           = "*" # Allow access to all API key secrets
      })
    }
  ]

  additional_tags = var.additional_tags
}

# ==============================================================================
# ORCHESTRATOR SECURITY GROUP - Network access for ECS orchestrator
# ==============================================================================

module "orchestrator_security_group" {
  source = "../modules/security_groups"

  stack_name = var.stack_name
  env        = var.env
  vpc_id     = local.vpc_id
  aws_region = var.aws_region
  stack_tool = "orchestrator"

  # Allow all traffic from VPC CIDR
  ingress_rules = [
    {
      description      = "Allow all inbound traffic from VPC CIDR"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = [var.vpc_cidr]
      ipv6_cidr_blocks = []
      security_groups  = []
    }
  ]

  # Allow all outbound traffic (Lambda Function URLs, Bedrock, Redis, Aurora)
  egress_rules = [
    {
      description      = "Allow all outbound traffic to Lambda MCPs, Bedrock, Redis, Aurora"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    }
  ]

  additional_tags = merge(var.additional_tags, {
    Purpose = "orchestrator-ecs-service"
  })
}

# ==============================================================================
# WHATSAPP AUTH HANDLER LAMBDA - Authentication layer before SQS
# ==============================================================================

module "whatsapp_auth_lambda" {
  source = "../modules/whatsapp_auth_lambda"

  function_name = "${var.stack_name}-${var.env}-whatsapp-auth-handler"
  env           = var.env

  # S3-based deployment configuration
  use_s3_deployment = true
  s3_bucket         = local.lambda_packages_bucket
  s3_key            = "auth-handlers/python_3.13/whatsapp_auth_handler.zip"
  s3_object_version = data.aws_s3_object.whatsapp_auth_function.version_id

  # VPC Configuration (Aurora access)
  private_subnet_ids = local.private_subnet_ids
  security_group_ids = [module.lambda_internal_security_group.security_group_id]

  # Database and Queue
  postgres_secret_arn = local.postgres_credentials_arn
  sqs_queue_url       = module.whatsapp_sqs.queue_url
  sqs_queue_arn       = module.whatsapp_sqs.queue_arn
  base_url            = var.ridhatech_base_url

  # Twilio credentials (for grace period reminders)
  twilio_secret_arn = var.twilio_secret_arn

  # API Gateway permission
  enable_api_gateway_permission = true
  api_gateway_execution_arn     = module.whatsapp_api_gateway.execution_arn

  # Runtime configuration
  lambda_runtime     = "python3.13"
  lambda_timeout     = 30
  lambda_memory_size = 256

  additional_tags = merge(var.additional_tags, {
    Service     = "whatsapp-auth"
    PackageETag = data.aws_s3_object.whatsapp_auth_function.etag
  })

  depends_on = [
    module.whatsapp_sqs,
    module.lambda_internal_security_group
  ]
}

# ==============================================================================
# WHATSAPP NOTIFICATION RETRY QUEUE - For failed payment confirmation messages
# ==============================================================================
# NOTE: Created BEFORE payment_webhook_lambda so that the queue URL can be passed
# to the Lambda. Uses account-level permissions initially; specific role permission
# can be added later via the payment_webhook_role_arn variable.

module "whatsapp_notification_dlq" {
  source = "../modules/whatsapp_notification_dlq"

  stack_name = var.stack_name
  env        = var.env

  # IAM role that can send messages to this queue
  # Empty initially - account-level access via root is sufficient
  # Can be updated after payment_webhook_lambda exists
  payment_webhook_role_arn = ""

  # Twilio credentials for notification retry Lambda
  twilio_secret_arn = var.twilio_secret_arn

  # Lambda package location
  lambda_s3_bucket = local.lambda_packages_bucket
  lambda_s3_key    = "auth-handlers/python_3.13/notification_retry_handler.zip"

  log_retention_days = 14

  additional_tags = var.additional_tags
}

# ==============================================================================
# PAYMENT WEBHOOK HANDLER LAMBDA - Handles Stripe, Paystack, Flutterwave webhooks
# ==============================================================================

module "payment_webhook_lambda" {
  source = "../modules/payment_webhook_lambda"

  function_name = "${var.stack_name}-${var.env}-payment-webhook-handler"
  env           = var.env

  # S3-based deployment configuration
  use_s3_deployment    = true
  s3_bucket            = local.lambda_packages_bucket
  s3_key               = "auth-handlers/python_3.13/payment_webhook_handler.zip"
  s3_object_version    = data.aws_s3_object.payment_webhook_function.version_id
  s3_source_code_hash  = data.aws_s3_object.payment_webhook_function.etag

  # VPC Configuration (Aurora access)
  private_subnet_ids = local.private_subnet_ids
  security_group_ids = [module.lambda_internal_security_group.security_group_id]

  # Database credentials
  postgres_secret_arn = local.postgres_credentials_arn

  # Payment provider credentials
  stripe_webhook_secret      = var.stripe_webhook_secret
  paystack_secret_key        = var.paystack_secret_key
  flutterwave_webhook_secret = var.flutterwave_webhook_secret

  # Twilio credentials for WhatsApp confirmation messages
  twilio_secret_arn = var.twilio_secret_arn

  # Notification queue (for failed WhatsApp messages)
  notification_queue_url = module.whatsapp_notification_dlq.retry_queue_url
  notification_queue_arn = module.whatsapp_notification_dlq.retry_queue_arn

  # API Gateway permission
  api_gateway_execution_arn = module.whatsapp_api_gateway.execution_arn

  # Runtime configuration
  lambda_runtime     = "python3.13"
  lambda_timeout     = 30
  lambda_memory_size = 256

  additional_tags = merge(var.additional_tags, {
    Service     = "payment-webhook"
    PackageETag = data.aws_s3_object.payment_webhook_function.etag
  })

  depends_on = [
    module.lambda_internal_security_group,
    module.whatsapp_notification_dlq
  ]
}

# ==============================================================================
# PAYMENT SESSION HANDLER LAMBDA - Creates Flutterwave checkout sessions
# ==============================================================================

module "payment_session_lambda" {
  source = "../modules/payment_session_lambda"

  function_name = "${var.stack_name}-${var.env}-payment-session-handler"
  env           = var.env

  # S3-based deployment configuration
  s3_bucket        = local.lambda_packages_bucket
  s3_key           = "auth-handlers/python_3.13/payment_session_handler.zip"
  source_code_hash = data.aws_s3_object.payment_session_function.etag

  # Flutterwave credentials
  flutterwave_secret_arn = var.flutterwave_secret_arn

  # Redirect URL after payment completion
  redirect_url = "${var.ridhatech_base_url}/payment-success"

  # API Gateway permission
  enable_api_gateway_permission = true
  api_gateway_execution_arn     = module.whatsapp_api_gateway.execution_arn

  # Runtime configuration
  lambda_runtime     = "python3.13"
  lambda_timeout     = 30
  lambda_memory_size = 128

  additional_tags = merge(var.additional_tags, {
    Service     = "payment-session"
    PackageETag = data.aws_s3_object.payment_session_function.etag
  })
}

# ==============================================================================
# PAYMENT API GATEWAY RESOURCES - /payments/create-session endpoint
# ==============================================================================

# /payments resource
resource "aws_api_gateway_resource" "payments" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  parent_id   = module.whatsapp_api_gateway.root_resource_id
  path_part   = "payments"
}

# /payments/create-session resource
resource "aws_api_gateway_resource" "create_session" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  parent_id   = aws_api_gateway_resource.payments.id
  path_part   = "create-session"
}

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "create_session_options" {
  rest_api_id   = module.whatsapp_api_gateway.rest_api_id
  resource_id   = aws_api_gateway_resource.create_session.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# OPTIONS mock integration for CORS
resource "aws_api_gateway_integration" "create_session_options" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  resource_id = aws_api_gateway_resource.create_session.id
  http_method = aws_api_gateway_method.create_session_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# OPTIONS method response
resource "aws_api_gateway_method_response" "create_session_options_200" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  resource_id = aws_api_gateway_resource.create_session.id
  http_method = aws_api_gateway_method.create_session_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# OPTIONS integration response
resource "aws_api_gateway_integration_response" "create_session_options" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  resource_id = aws_api_gateway_resource.create_session.id
  http_method = aws_api_gateway_method.create_session_options.http_method
  status_code = aws_api_gateway_method_response.create_session_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# POST /payments/create-session method
resource "aws_api_gateway_method" "create_session_post" {
  rest_api_id   = module.whatsapp_api_gateway.rest_api_id
  resource_id   = aws_api_gateway_resource.create_session.id
  http_method   = "POST"
  authorization = "NONE"
}

# POST Lambda proxy integration
resource "aws_api_gateway_integration" "create_session_lambda" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  resource_id = aws_api_gateway_resource.create_session.id
  http_method = aws_api_gateway_method.create_session_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.payment_session_lambda.invoke_arn

  timeout_milliseconds = 29000
}

# Lambda permission for API Gateway to invoke payment session handler
resource "aws_lambda_permission" "payment_session_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke-PaymentSession"
  action        = "lambda:InvokeFunction"
  function_name = module.payment_session_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.whatsapp_api_gateway.execution_arn}/*/*"
}

# ==============================================================================
# PAYMENT WEBHOOK ROUTE - /payments/webhook (for Flutterwave webhooks)
# ==============================================================================

# /payments/webhook resource
resource "aws_api_gateway_resource" "payment_webhook" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  parent_id   = aws_api_gateway_resource.payments.id
  path_part   = "webhook"
}

# POST /payments/webhook method
resource "aws_api_gateway_method" "payment_webhook_post" {
  rest_api_id   = module.whatsapp_api_gateway.rest_api_id
  resource_id   = aws_api_gateway_resource.payment_webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

# POST Lambda proxy integration for payment webhook
resource "aws_api_gateway_integration" "payment_webhook_lambda" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id
  resource_id = aws_api_gateway_resource.payment_webhook.id
  http_method = aws_api_gateway_method.payment_webhook_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.payment_webhook_lambda.invoke_arn

  timeout_milliseconds = 29000
}

# Lambda permission for API Gateway to invoke payment webhook handler
resource "aws_lambda_permission" "payment_webhook_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke-PaymentWebhook"
  action        = "lambda:InvokeFunction"
  function_name = module.payment_webhook_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.whatsapp_api_gateway.execution_arn}/*/*"
}

# Redeploy API Gateway to include new payment routes
# This deployment updates the prod stage with the new routes
resource "aws_api_gateway_deployment" "payment_routes" {
  rest_api_id = module.whatsapp_api_gateway.rest_api_id

  # Associate this deployment with the existing prod stage
  # This updates the stage to include the new payment routes
  # Note: stage_name is deprecated but aws_api_gateway_stage would conflict
  # with the one in the module. This approach works by updating the existing stage.
  stage_name  = "prod"
  description = "Deployment with payment routes"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.payments.id,
      aws_api_gateway_resource.create_session.id,
      aws_api_gateway_method.create_session_post.id,
      aws_api_gateway_integration.create_session_lambda.id,
      aws_api_gateway_method.create_session_options.id,
      aws_api_gateway_integration.create_session_options.id,
      # Payment webhook route
      aws_api_gateway_resource.payment_webhook.id,
      aws_api_gateway_method.payment_webhook_post.id,
      aws_api_gateway_integration.payment_webhook_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.create_session_post,
    aws_api_gateway_method.create_session_options,
    aws_api_gateway_integration.create_session_lambda,
    aws_api_gateway_integration.create_session_options,
    aws_api_gateway_integration_response.create_session_options,
    # Payment webhook dependencies
    aws_api_gateway_method.payment_webhook_post,
    aws_api_gateway_integration.payment_webhook_lambda,
  ]
}
