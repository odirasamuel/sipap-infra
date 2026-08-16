# ============================================================================
# DATABASE QUERY ECS TASK (REPLACES LAMBDA)
# ============================================================================
# On-demand ECS Fargate task for database queries and exploration.
# Triggered manually via GitHub Actions workflow.
#
# Advantages over Lambda:
# - No timeout limits (Lambda was timing out on DB connection)
# - Full output to CloudWatch logs
# - Supports custom SQL queries
#
# Triggered via:
# - GitHub Actions workflow (workflow_dispatch)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster --task-definition sipap-dev-db-query
#
# Note: ECR repository "db-query" is created in main.tf via the ecr module

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for db_query task (allows container to call AWS APIs)
resource "aws_iam_role" "db_query_task_role" {
  name = "${var.stack_name}-${var.env}-db-query-task-role"

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

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-query-task-role"
    },
    var.additional_tags
  )
}

# IAM Policy for db_query task (Secrets Manager + CloudWatch Logs)
resource "aws_iam_role_policy" "db_query_task_policy" {
  name = "db-query-permissions"
  role = aws_iam_role.db_query_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.db_query.arn}:*"
        ]
      }
    ]
  })
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "db_query" {
  family                   = "${var.stack_name}-${var.env}-db-query"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"   # 0.25 vCPU
  memory                   = "512"   # 0.5 GB
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.db_query_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "db-query"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]}:latest"

      # Use Dockerfile's ENTRYPOINT + CMD (no command override needed)
      # ENTRYPOINT: ["python", "-m", "sipap_batch_scraper.jobs.db_query"]
      # CMD: ["--ecs"]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.env
        },
        {
          name  = "AURORA_HOST"
          value = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
        },
        {
          name  = "AURORA_PORT"
          value = "5432"
        },
        {
          name  = "AURORA_DATABASE"
          value = "sipap_dev"
        },
        {
          name  = "AURORA_USER"
          value = "sipap_admin"
        },
        {
          name  = "MODE"
          value = "query"  # Default mode, can be overridden
        }
      ]

      secrets = [
        {
          name      = "AURORA_PASSWORD"
          valueFrom = "${data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.db_query.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db-query"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name    = "${var.stack_name}-${var.env}-db-query"
      Purpose = "database-exploration"
    },
    var.additional_tags
  )
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "db_query" {
  name              = "/ecs/${var.stack_name}-${var.env}-db-query"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-query-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "db_query_repository_url" {
  description = "ECR repository URL for db_query container"
  value       = data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]
}

output "db_query_task_definition_arn" {
  description = "ECS task definition ARN for db_query"
  value       = aws_ecs_task_definition.db_query.arn
}

output "db_query_task_definition_family" {
  description = "ECS task definition family name"
  value       = aws_ecs_task_definition.db_query.family
}

output "db_query_log_group" {
  description = "CloudWatch log group for db_query"
  value       = aws_cloudwatch_log_group.db_query.name
}
