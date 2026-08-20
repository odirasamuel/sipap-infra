# ============================================================================
# DB QUERY ECS TASK
# ============================================================================
# On-demand ECS Fargate task for executing custom SQL queries against Aurora.
# Triggered via GitHub Actions workflow for database maintenance tasks.
# ============================================================================

locals {
  db_query_name = "${var.stack_name}-${var.env}-db-query"
}

# ============================================================================
# IAM ROLE FOR DB QUERY TASK
# ============================================================================

resource "aws_iam_role" "db_query_task_role" {
  name = "${local.db_query_name}-task-role"

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
    Name        = "${local.db_query_name}-task-role"
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "db_query_task_policy" {
  name = "db-query-permissions"
  role = aws_iam_role.db_query_task_role.id

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
        Resource = "${aws_cloudwatch_log_group.db_query.arn}:*"
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "db_query" {
  name              = "/ecs/${local.db_query_name}"
  retention_in_days = 14

  tags = {
    Name        = local.db_query_name
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "db_query" {
  family                   = local.db_query_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.db_query_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "db-query"
      image     = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["batch-scraper"]}:latest"
      essential = true

      command = ["python", "-m", "sipap_batch_scraper.jobs.db_query"]

      environment = [
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "POSTGRES_HOST"
          value = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
        },
        {
          name  = "POSTGRES_PORT"
          value = "5432"
        },
        {
          name  = "POSTGRES_DB"
          value = data.terraform_remote_state.root.outputs.aurora_database_name
        },
        {
          name  = "POSTGRES_CREDENTIALS_ARN"
          value = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.db_query.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = local.db_query_name
    Environment = var.env
    Project     = "SIPAP"
    ManagedBy   = "Terraform"
  }
}
