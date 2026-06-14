# SIPAP Infrastructure - Main Terraform Configuration
# Following Sentinel's modular pattern

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

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policies = [
    {
      name = "secrets-access"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "secretsmanager:GetSecretValue",
              "ssm:GetParameters"
            ]
            Resource = "*"
          }
        ]
      })
    }
  ]

  additional_tags = var.additional_tags
}

# SQS Access Role (for services to send messages)
module "sqs_sender_role" {
  source = "./modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "sqs-sender"
  role_description = "Role for services to send messages to SQS queues"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policies = [
    {
      name = "sqs-send-messages"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "sqs:SendMessage",
              "sqs:GetQueueUrl"
            ]
            Resource = "*"
          }
        ]
      })
    }
  ]

  additional_tags = var.additional_tags
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
  min_capacity    = 0.5
  max_capacity    = 1.0

  # Standard RDS configuration (used when use_serverless = false)
  use_serverless  = var.aurora_use_serverless
  instance_class  = var.aurora_instance_class

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
    }
  ]

  additional_tags = var.additional_tags
}

# ECS Cluster (empty for now, services added in Phase 4)
module "ecs_cluster" {
  source = "./modules/ecs"

  stack_name              = var.stack_name
  env                     = var.env
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.subnets.private_subnet_ids
  task_execution_role_arn = module.ecs_task_execution_role.role_arn
  services                = [] # Services added in Phase 4
  additional_tags         = var.additional_tags
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
