# Database Migration Resources
# One-time setup for running database migrations via ECS

# ECR Repository for migration container
resource "aws_ecr_repository" "migrations" {
  name                 = "sipap-migrations"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    {
      Name = "${var.stack_name}-migrations"
    },
    var.additional_tags
  )
}

# ECS Task Definition for migrations
resource "aws_ecs_task_definition" "migrations" {
  family                   = "${var.stack_name}-${var.env}-migrations"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 512 MB
  execution_role_arn       = module.ecs_task_execution_role.role_arn

  container_definitions = jsonencode([
    {
      name  = "migrations"
      image = "${aws_ecr_repository.migrations.repository_url}:latest"

      environment = [
        {
          name  = "DB_HOST"
          value = module.aurora.endpoint
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = var.database_name
        },
        {
          name  = "DB_USER"
          value = var.db_master_username
        },
        {
          name  = "SECRET_ARN"
          value = module.aurora.password_secret_arn
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.stack_name}-${var.env}-migrations"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "migrations"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-migrations"
    },
    var.additional_tags
  )
}

# CloudWatch Log Group for migration logs
resource "aws_cloudwatch_log_group" "migrations" {
  name              = "/ecs/${var.stack_name}-${var.env}-migrations"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-migrations-logs"
    },
    var.additional_tags
  )
}

# Output migration repository URL
output "migrations_repository_url" {
  description = "ECR repository URL for migration container"
  value       = aws_ecr_repository.migrations.repository_url
}

output "migrations_task_definition" {
  description = "ECS task definition ARN for migrations"
  value       = aws_ecs_task_definition.migrations.arn
}
