# ============================================================================
# DATABASE MIGRATIONS ECS TASK
# ============================================================================
# On-demand ECS Fargate task for running Alembic database migrations.
# Triggered via GitHub Actions workflow.
# ============================================================================

locals {
  migrations_name = "${var.stack_name}-${var.env}-migrations"
}

# ============================================================================
# IAM ROLE FOR MIGRATIONS TASK
# ============================================================================

resource "aws_iam_role" "migrations_task_role" {
  name = "${local.migrations_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${local.migrations_name}-task-role"
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "migrations_task_policy" {
  name = "migrations-permissions"
  role = aws_iam_role.migrations_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        ]
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.migrations.arn}:*"
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "migrations" {
  name              = "/ecs/${local.migrations_name}"
  retention_in_days = 14

  tags = {
    Name        = local.migrations_name
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "migrations" {
  family                   = local.migrations_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.migrations_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "migrations"
      image     = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["migrations"]}:latest"
      essential = true

      environment = [
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "DB_HOST"
          value = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = data.terraform_remote_state.root.outputs.aurora_database_name
        },
        {
          name  = "DB_USER"
          value = "sipap_admin"
        },
        {
          name  = "SECRET_ARN"
          value = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.migrations.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "migrations"
        }
      }
    }
  ])

  tags = {
    Name        = local.migrations_name
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "migrations_task_definition_arn" {
  description = "ARN of the migrations task definition"
  value       = aws_ecs_task_definition.migrations.arn
}

output "migrations_task_role_arn" {
  description = "ARN of the migrations task IAM role"
  value       = aws_iam_role.migrations_task_role.arn
}
