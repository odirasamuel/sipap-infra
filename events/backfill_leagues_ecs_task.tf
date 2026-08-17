# ============================================================================
# BACKFILL LEAGUES ECS TASK
# ============================================================================
# On-demand ECS Fargate task to backfill leagues.external_id from API-Football.
#
# This is critical for predictions - without external_id, we can't fetch
# team statistics from API-Football.
#
# Matching strategies:
# 1. Exact match: name + country
# 2. Name-only match (when unambiguous)
# 3. Fuzzy match (normalized names)
# 4. Fixture-based (optional, uses API-Football fixture lookup)
#
# Triggered via:
# - GitHub Actions workflow (workflow_dispatch)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster --task-definition sipap-dev-backfill-leagues
#
# Environment variables:
# - FIXTURE_FALLBACK=true: Enable fixture-based lookup for unmatched leagues
# - MAX_FIXTURE_LOOKUPS=500: Max API calls for fixture fallback
# - DRY_RUN=true: Report what would change without updating

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for backfill_leagues task
resource "aws_iam_role" "backfill_leagues_task_role" {
  name = "${var.stack_name}-${var.env}-backfill-leagues-task-role"

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
      Name = "${var.stack_name}-${var.env}-backfill-leagues-task-role"
    },
    var.additional_tags
  )
}

# IAM Policy for backfill_leagues task (Secrets Manager + CloudWatch Logs)
resource "aws_iam_role_policy" "backfill_leagues_task_policy" {
  name = "backfill-leagues-permissions"
  role = aws_iam_role.backfill_leagues_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn,
          data.terraform_remote_state.root.outputs.api_keys_secret_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.backfill_leagues.arn}:*"
        ]
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "backfill_leagues" {
  name              = "/ecs/${var.stack_name}-${var.env}-backfill-leagues"
  retention_in_days = 14

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-leagues-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "backfill_leagues" {
  family                   = "${var.stack_name}-${var.env}-backfill-leagues"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"   # 0.5 vCPU (more CPU for API calls)
  memory                   = "1024"  # 1 GB
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.backfill_leagues_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backfill-leagues"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]}:latest"

      # Override command to run backfill_leagues instead of db_query
      command = [
        "python", "-m", "sipap_batch_scraper.jobs.backfill_leagues"
      ]

      environment = [
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
          value = data.terraform_remote_state.root.outputs.aurora_database_name
        },
        {
          name  = "FIXTURE_FALLBACK"
          value = "true"
        },
        {
          name  = "MAX_FIXTURE_LOOKUPS"
          value = "500"
        }
      ]

      secrets = [
        {
          name      = "AURORA_USER"
          valueFrom = "${data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn}:username::"
        },
        {
          name      = "AURORA_PASSWORD"
          valueFrom = "${data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn}:password::"
        },
        {
          name      = "API_FOOTBALL_KEY"
          valueFrom = "${data.terraform_remote_state.root.outputs.api_keys_secret_arn}:API_FOOTBALL_KEY::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backfill_leagues.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backfill-leagues"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-leagues"
    },
    var.additional_tags
  )
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "backfill_leagues_task_definition_arn" {
  description = "ARN of the backfill-leagues ECS task definition"
  value       = aws_ecs_task_definition.backfill_leagues.arn
}

output "backfill_leagues_log_group" {
  description = "CloudWatch log group for backfill-leagues"
  value       = aws_cloudwatch_log_group.backfill_leagues.name
}
