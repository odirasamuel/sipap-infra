# SIPAP Infrastructure - Main Terraform Configuration

# ============================================================================
# LOCALS FOR POLICY CHANGE TRACKING & ECS SERVICE CONFIGURATION
# ============================================================================
# Compute hashes of policy files to detect changes

locals {
  ecs_secrets_access_policy_hash = filesha256("${path.module}/modules/policies/ecs_secrets_access_policy.json")
  sqs_send_messages_policy_hash  = filesha256("${path.module}/modules/policies/sqs_send_messages_policy.json")

  # Pull core_deploy outputs for ECS service configuration
  # Only populated if remote state exists and var.ecs_services is not empty
  core_deploy_outputs = try(data.terraform_remote_state.core_deploy.outputs, {})
}

# ============================================================================
# REMOTE STATE - Reference core_deploy outputs for ECS services
# ============================================================================

data "terraform_remote_state" "core_deploy" {
  backend = "s3"

  config = {
    bucket  = "sipap-dev-tf-state-bucket"
    key     = "sipap-dev-core-deploy-tf-state"
    region  = "us-west-1"
    profile = "odiraaws"
  }
}

# ============================================================================
# NETWORKING
# ============================================================================

# VPC
module "vpc" {
  source = "./modules/vpc"

  stack_name      = var.stack_name
  env             = var.env
  cidr_block      = var.vpc_cidr
  additional_tags = var.additional_tags
}

# Subnets
module "subnets" {
  source = "./modules/subnets"

  stack_name           = var.stack_name
  env                  = var.env
  vpc_id               = module.vpc.vpc_id
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  additional_tags      = var.additional_tags
}

# Internet Gateway
module "internet_gateway" {
  source = "./modules/internet_gateway"

  stack_name        = var.stack_name
  env               = var.env
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.subnets.public_subnet_ids
  additional_tags   = var.additional_tags
}

# NAT Gateway
module "nat_gateway" {
  source = "./modules/nat_gateway"

  stack_name         = var.stack_name
  env                = var.env
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.subnets.public_subnet_ids
  private_subnet_ids = module.subnets.private_subnet_ids
  nat_gateway_count  = var.nat_gateway_count
  additional_tags    = var.additional_tags
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

# ElastiCache Security Group
module "elasticache_sg" {
  source = "./modules/security_groups"

  stack_name = var.stack_name
  env        = var.env
  vpc_id     = module.vpc.vpc_id
  aws_region = var.aws_region
  stack_tool = "elasticache"

  ingress_rules = [
    {
      description      = "Redis from VPC"
      from_port        = 6379
      to_port          = 6379
      protocol         = "tcp"
      cidr_blocks      = [var.vpc_cidr]
      ipv6_cidr_blocks = []
      security_groups  = []
    }
  ]

  egress_rules = [
    {
      description      = "Allow all outbound"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    }
  ]

  additional_tags = var.additional_tags
}

# ECS Tasks Security Group
module "ecs_tasks_sg" {
  source = "./modules/security_groups"

  stack_name = var.stack_name
  env        = var.env
  vpc_id     = module.vpc.vpc_id
  aws_region = var.aws_region
  stack_tool = "ecs-tasks"

  ingress_rules = [
    {
      description      = "Allow traffic within VPC"
      from_port        = 0
      to_port          = 65535
      protocol         = "tcp"
      cidr_blocks      = [var.vpc_cidr]
      ipv6_cidr_blocks = []
      security_groups  = []
    }
  ]

  egress_rules = [
    {
      description      = "Allow all outbound"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    }
  ]

  additional_tags = var.additional_tags
}

# ============================================================================
# IAM ROLES
# ============================================================================

# ECS Task Execution Role (for pulling images, writing logs)
module "ecs_task_execution_role" {
  source = "./modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "ecs-task-execution"
  role_description = "ECS task execution role for pulling images and writing logs"

  assume_role_policy = templatefile("${path.module}/modules/assume_role_policies/ecs_task_assume_role.json", {})

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policies = [
    {
      name   = "secrets-access"
      policy = templatefile("${path.module}/modules/policies/ecs_secrets_access_policy.json", {})
    }
  ]

  additional_tags = merge(var.additional_tags, {
    EcsSecretsAccessPolicyHash = local.ecs_secrets_access_policy_hash
  })
}

# SQS Access Role (for services to send messages)
module "sqs_sender_role" {
  source = "./modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "sqs-sender"
  role_description = "Role for services to send messages to SQS queues"

  assume_role_policy = templatefile("${path.module}/modules/assume_role_policies/ecs_task_assume_role.json", {})

  inline_policies = [
    {
      name   = "sqs-send-messages"
      policy = templatefile("${path.module}/modules/policies/sqs_send_messages_policy.json", {})
    }
  ]

  additional_tags = merge(var.additional_tags, {
    SqsSendMessagesPolicyHash = local.sqs_send_messages_policy_hash
  })
}

# ============================================================================
# DATA LAYER
# ============================================================================

# Database (Aurora Serverless v2 or Standard RDS)
module "aurora" {
  source = "./modules/rds"

  stack_name      = var.stack_name
  env             = var.env
  database_name   = var.database_name
  master_username = var.db_master_username

  # Serverless configuration (used when use_serverless = true)
  min_capacity = 0.5
  max_capacity = 1.0

  # Standard RDS configuration (used when use_serverless = false)
  use_serverless = var.aurora_use_serverless
  instance_class = var.aurora_instance_class

  subnet_ids      = module.subnets.private_subnet_ids
  vpc_id          = module.vpc.vpc_id
  allowed_cidrs   = [var.vpc_cidr]
  additional_tags = var.additional_tags
}

# ElastiCache (Serverless or Standard Instance)
module "elasticache" {
  source = "./modules/elasticache"

  cache_name           = "${var.stack_name}-${var.env}-redis"
  engine               = "redis"
  major_engine_version = "7"
  description          = "SIPAP Redis cache for session storage and caching"
  security_group_ids   = [module.elasticache_sg.security_group_id]
  subnet_ids           = module.subnets.private_subnet_ids

  # Serverless configuration (used when use_serverless = true)
  cache_usage_limits = {
    data_storage = {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second = {
      maximum = 1000
    }
  }

  # Standard instance configuration (used when use_serverless = false)
  use_serverless = var.elasticache_use_serverless
  node_type      = var.elasticache_node_type

  additional_tags = var.additional_tags
}

# ============================================================================
# CONTAINER INFRASTRUCTURE
# ============================================================================

# ECR Repositories
module "ecr" {
  source = "./modules/ecr"

  stack_name = var.stack_name
  env        = var.env

  repositories = [
    {
      name = "orchestrator"
    },
    {
      name = "odds-streaming"
    },
    {
      name = "sports-data-mcp"
    },
    {
      name = "odds-intelligence-mcp"
    },
    {
      name = "news-context-mcp"
    },
    {
      name = "weather-data-mcp"
    },
    {
      name = "historical-data-mcp"
    },
    {
      name = "batch-scraper"
    }
  ]

  additional_tags = var.additional_tags
}

# ECS Cluster with orchestrator service
module "ecs_cluster" {
  source = "./modules/ecs"

  stack_name              = var.stack_name
  env                     = var.env
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.subnets.private_subnet_ids
  task_execution_role_arn = module.ecs_task_execution_role.role_arn

  # Transform services from tfvars, injecting dynamic values from remote state
  services = [
    for service in var.ecs_services : {
      name          = service.name
      image         = service.image
      cpu           = service.cpu
      memory        = service.memory
      desired_count = service.desired_count
      task_role_arn = try(local.core_deploy_outputs.orchestrator_task_role_arn, null)

      port_mappings = service.port_mappings

      # Merge static env vars from tfvars with dynamic values from remote state
      environment_variables = concat(
        service.environment_variables,
        [
          {
            name  = "ORCHESTRATOR_MODE"
            value = "daemon"  # daemon (SQS polling) or api (FastAPI server)
          },
          {
            name  = "DATA_MCP_URL"
            value = try(local.core_deploy_outputs.data_mcp_function_url, "")
          },
          {
            name  = "INTELLIGENCE_MCP_URL"
            value = try(local.core_deploy_outputs.intelligence_mcp_function_url, "")
          },
          {
            name  = "BEDROCK_PROFILE_ARN"
            value = try(local.core_deploy_outputs.bedrock_orchestrator_profile_arn, "")
          },
          {
            name  = "REDIS_HOST"
            value = module.elasticache.configuration_endpoint
          },
          {
            name  = "REDIS_PORT"
            value = tostring(module.elasticache.port)
          },
          {
            name  = "SQS_QUEUE_URL"
            value = try(local.core_deploy_outputs.whatsapp_queue_url, "")
          },
          {
            name  = "POSTGRES_HOST"
            value = module.aurora.endpoint
          },
          {
            name  = "POSTGRES_DB"
            value = var.database_name
          },
          {
            name  = "TWILIO_SECRET_ARN"
            value = "arn:aws:secretsmanager:us-east-1:810278669998:secret:/sipap/dev/twilio-credentials-tngBnx"
          }
        ]
      )

      # Merge secrets from tfvars with Aurora credentials
      secrets = concat(
        service.secrets,
        [
          {
            name       = "POSTGRES_CREDENTIALS"
            value_from = module.aurora_credentials_secret.secret_arn
          }
        ]
      )

      security_group_ids = [try(local.core_deploy_outputs.orchestrator_security_group_id, "")]

      load_balancer_config = null # No ALB for now

      deployment_configuration         = service.deployment_configuration
      health_check                     = service.health_check
      enable_deployment_circuit_breaker = service.enable_deployment_circuit_breaker
      enable_deployment_rollback       = service.enable_deployment_rollback

      # Optional fields with defaults
      efs_volumes                    = null
      mount_points                   = null
      command                        = null
      entrypoint                     = null
      container_definition_overrides = null
    }
  ]

  enable_execute_command = true # For debugging/testing via ECS Exec

  additional_tags = var.additional_tags
}

# ============================================================================
# QUEUING
# ============================================================================

# Prediction Queue (Standard SQS, non-FIFO for high throughput)
resource "aws_sqs_queue" "prediction_queue" {
  name                       = "${var.stack_name}-${var.env}-prediction-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 10      # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.prediction_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge({
    Name = "${var.stack_name}-${var.env}-prediction-queue"
  }, var.additional_tags)
}

# Prediction Dead Letter Queue
resource "aws_sqs_queue" "prediction_dlq" {
  name                      = "${var.stack_name}-${var.env}-prediction-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge({
    Name = "${var.stack_name}-${var.env}-prediction-dlq"
  }, var.additional_tags)
}

# ============================================================================
# SECRETS MANAGER
# ============================================================================

# Aurora Credentials Secret
module "aurora_credentials_secret" {
  source = "./modules/create_secret"

  secret_name        = "${var.stack_name}/${var.env}/aurora-credentials"
  secret_description = "Aurora PostgreSQL credentials for SIPAP"
  replica_region     = null

  secret_string = jsonencode({
    username = var.db_master_username
    password = module.aurora.master_password
    host     = module.aurora.endpoint
    port     = "5432"
    database = var.database_name
  })

  additional_tags = merge(
    {
      Environment = var.env
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# API Keys Secret (Placeholder - populated manually via AWS CLI)
module "api_keys_secret" {
  source = "./modules/create_secret"

  secret_name        = "${var.stack_name}/${var.env}/api-keys"
  secret_description = "API keys for SIPAP (Football-Data.org, The Odds API, TheSportsDB)"
  replica_region     = null

  # Empty secret - will be populated manually via AWS CLI with profile "odiraaws"
  secret_string = jsonencode({
    FOOTBALL_DATA_KEY = ""
    ODDS_API_KEY      = ""
    THESPORTSDB_KEY   = "123"
  })

  additional_tags = merge(
    {
      Environment = var.env
      ManagedBy   = "terraform"
      PopulatedBy = "manual-cli"
    },
    var.additional_tags
  )
}
