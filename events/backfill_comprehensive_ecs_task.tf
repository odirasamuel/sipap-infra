# ============================================================================
# COMPREHENSIVE BACKFILL ECS TASK
# ============================================================================
# On-demand ECS Fargate task to backfill standings and team_statistics
# for all leagues across all seasons (2019-2026).
#
# This is critical for predictions - without standings and team_statistics,
# the prediction engine cannot calculate team performance metrics.
#
# Environment variables:
# - SEASONS: Comma-separated list (e.g., "2024,2025,2026")
# - SEASON_START/SEASON_END: Range of seasons (default: 2019-2026)
# - SKIP_STANDINGS: Set to "true" to skip standings backfill
# - SKIP_TEAM_STATS: Set to "true" to skip team stats backfill
# - DRY_RUN: Set to "true" to report without making changes
# - BATCH_DELAY_MS: Delay between API calls (default: 400)
# - MAX_LEAGUES: Limit leagues to process (for testing)
#
# Triggered via:
# - GitHub Actions workflow (workflow_dispatch)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster \
#           --task-definition sipap-dev-backfill-comprehensive \
#           --launch-type FARGATE \
#           --network-configuration "awsvpcConfiguration={...}" \
#           --overrides '{"containerOverrides":[{"name":"backfill-comprehensive","environment":[{"name":"SEASONS","value":"2026"}]}]}'

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for backfill_comprehensive task
resource "aws_iam_role" "backfill_comprehensive_task_role" {
  name = "${var.stack_name}-${var.env}-backfill-comprehensive-task-role"

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
      Name = "${var.stack_name}-${var.env}-backfill-comprehensive-task-role"
    },
    var.additional_tags
  )
}

# IAM Policy for backfill_comprehensive task (Secrets Manager + CloudWatch Logs)
resource "aws_iam_role_policy" "backfill_comprehensive_task_policy" {
  name = "backfill-comprehensive-permissions"
  role = aws_iam_role.backfill_comprehensive_task_role.id

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
          "${aws_cloudwatch_log_group.backfill_comprehensive.arn}:*"
        ]
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "backfill_comprehensive" {
  name              = "/ecs/${var.stack_name}-${var.env}-backfill-comprehensive"
  retention_in_days = 30  # Keep logs longer for analysis

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-comprehensive-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "backfill_comprehensive" {
  family                   = "${var.stack_name}-${var.env}-backfill-comprehensive"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"   # 1 vCPU (more CPU for processing)
  memory                   = "2048"   # 2 GB (more memory for batch operations)
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.backfill_comprehensive_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backfill-comprehensive"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]}:latest"

      # Override entrypoint to run backfill_comprehensive
      entryPoint = ["python", "-m", "sipap_batch_scraper.jobs.backfill_comprehensive", "--ecs"]
      command = []

      environment = [
        {
          name  = "PYTHONUNBUFFERED"
          value = "1"
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
          value = data.terraform_remote_state.root.outputs.aurora_database_name
        },
        # Default: All seasons 2019-2026
        {
          name  = "SEASON_START"
          value = "2019"
        },
        {
          name  = "SEASON_END"
          value = "2026"
        },
        # Rate limiting: 400ms between requests (2.5 req/sec)
        {
          name  = "BATCH_DELAY_MS"
          value = "400"
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
          "awslogs-group"         = aws_cloudwatch_log_group.backfill_comprehensive.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backfill-comprehensive"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-comprehensive"
    },
    var.additional_tags
  )
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "backfill_comprehensive_task_definition_arn" {
  description = "ARN of the backfill-comprehensive ECS task definition"
  value       = aws_ecs_task_definition.backfill_comprehensive.arn
}

output "backfill_comprehensive_log_group" {
  description = "CloudWatch log group for backfill-comprehensive"
  value       = aws_cloudwatch_log_group.backfill_comprehensive.name
}
