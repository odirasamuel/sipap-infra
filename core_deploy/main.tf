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
  visibility_timeout_seconds     = 60      # 1 minute (workflows complete in <10s, allows fast retries)
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

  # SQS integration
  sqs_queue_url = module.whatsapp_sqs.queue_url
  sqs_queue_arn = module.whatsapp_sqs.queue_arn

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
# DATA MCP DEPENDENCY LAYER - asyncpg for PostgreSQL
# ==============================================================================

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
  internal_lambda_environment_variables = {
    REDIS_ENDPOINT           = local.redis_endpoint
    REDIS_SSL                = "false"
    POSTGRES_HOST            = local.postgres_host
    POSTGRES_PORT            = "5432"
    POSTGRES_DB              = local.postgres_db
    POSTGRES_CREDENTIALS_ARN = local.postgres_credentials_arn
    LOG_LEVEL                = "INFO"
    # API-Football key for direct API access (Data MCP redesign 2026-08-19)
    API_FOOTBALL_KEY = jsondecode(data.aws_secretsmanager_secret_version.api_keys.secret_string)["API_FOOTBALL_KEY"]
  }

  internal_lambda_description = "SIPAP Data MCP Server - Sports data, fixtures, standings (v2.0 API-Football direct)"

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
