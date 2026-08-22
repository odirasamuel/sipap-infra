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
  allowed_cidrs   = [var.vpc_cidr, "99.33.74.242/32"]  # VPC + local IP for integration testing
  lambda_security_group_ids = [module.ecs_tasks_sg.security_group_id]  # Allow Lambda functions to access RDS
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
    },
    {
      name = "odds-updater"
    },
    {
      name = "db-query"
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
# ECS AUTOSCALING
# ============================================================================

# ECS Autoscaling for orchestrator-service
# Uses SQS queue depth as primary scaling metric (I/O bound workload)
module "ecs_autoscaling" {
  source = "./modules/ecs_autoscaling"

  stack_name   = var.stack_name
  env          = var.env
  cluster_name = module.ecs_cluster.cluster_name

  # Use AWS service-linked role for Application Auto Scaling
  # This role is automatically created by AWS when first using autoscaling
  service_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"

  ecs_services = [
    {
      name         = "orchestrator-service"
      service_name = "orchestrator-service"
      min_capacity = var.orchestrator_autoscaling.min_capacity
      max_capacity = var.orchestrator_autoscaling.max_capacity

      # Disable CPU/memory scaling (I/O bound workload - waits on Bedrock API)
      enable_cpu_scaling    = false
      enable_memory_scaling = false

      # Cooldowns optimized for long-running predictions (5-30 minutes)
      scale_in_cooldown  = 600  # 10 minutes - wait for predictions to complete
      scale_out_cooldown = 120  # 2 minutes - respond quickly to demand

      # SQS-based scaling configuration
      sqs_scaling_config = {
        queue_name                    = try(local.core_deploy_outputs.whatsapp_queue_name, "${var.stack_name}-${var.env}-whatsapp-messages.fifo")
        scale_up_threshold            = var.orchestrator_autoscaling.sqs_scale_up_threshold
        scale_down_threshold          = 0     # Scale down when queue empty
        scale_up_evaluation_periods   = 2     # 2 x 60s = 2 minutes sustained
        scale_down_evaluation_periods = 3     # 3 x 300s = 15 minutes sustained
        scale_up_period               = 60    # Check every minute for scale up
        scale_down_period             = 300   # Check every 5 minutes for scale down
      }
    }
  ]

  additional_tags = var.additional_tags

  depends_on = [module.ecs_cluster]
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

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
  secret_description = "API keys for SIPAP (API-Football, OpenWeather, NewsAPI)"
  replica_region     = null

  # Empty secret - will be populated manually via AWS CLI with profile "odiraaws"
  secret_string = jsonencode({
    API_FOOTBALL_KEY     = ""
    OPENWEATHER_API_KEY  = ""
    NEWS_API_KEY         = ""
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
