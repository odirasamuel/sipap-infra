# ============================================================================
# TEAMS EXTERNAL_ID BACKFILL ECS TASK
# ============================================================================
# On-demand ECS Fargate task to backfill teams.external_id from standings data.
#
# This links internal team UUIDs to API-Football external IDs, which is
# critical for the Data MCP to look up team_statistics.
#
# Environment variables:
# - DRY_RUN: Set to "true" to report without making changes
# - MATCH_THRESHOLD: Fuzzy match threshold (0-100, default: 85)
#
# Triggered via:
# - GitHub Actions workflow (workflow_dispatch)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster \
#           --task-definition sipap-dev-backfill-teams-external-id \
#           --launch-type FARGATE \
#           --network-configuration "awsvpcConfiguration={...}"

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for backfill_teams_external_id task
resource "aws_iam_role" "backfill_teams_external_id_task_role" {
  name = "${var.stack_name}-${var.env}-backfill-teams-ext-id-task-role"

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
      Name = "${var.stack_name}-${var.env}-backfill-teams-ext-id-task-role"
    },
    var.additional_tags
  )
}

# IAM Policy for backfill_teams_external_id task (Secrets Manager + CloudWatch Logs)
resource "aws_iam_role_policy" "backfill_teams_external_id_task_policy" {
  name = "backfill-teams-external-id-permissions"
  role = aws_iam_role.backfill_teams_external_id_task_role.id

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
          "${aws_cloudwatch_log_group.backfill_teams_external_id.arn}:*"
        ]
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "backfill_teams_external_id" {
  name              = "/ecs/${var.stack_name}-${var.env}-backfill-teams-external-id"
  retention_in_days = 14

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-teams-external-id-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "backfill_teams_external_id" {
  family                   = "${var.stack_name}-${var.env}-backfill-teams-external-id"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.backfill_teams_external_id_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "backfill-teams-external-id"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]}:latest"

      # Override entrypoint to run backfill_teams_external_id
      entryPoint = ["python", "-m", "sipap_batch_scraper.jobs.backfill_teams_external_id", "--ecs"]
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
        {
          name  = "MATCH_THRESHOLD"
          value = "85"
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
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backfill_teams_external_id.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backfill-teams-external-id"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-backfill-teams-external-id"
    },
    var.additional_tags
  )
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "backfill_teams_external_id_task_definition_arn" {
  description = "ARN of the backfill-teams-external-id ECS task definition"
  value       = aws_ecs_task_definition.backfill_teams_external_id.arn
}

output "backfill_teams_external_id_log_group" {
  description = "CloudWatch log group for backfill-teams-external-id"
  value       = aws_cloudwatch_log_group.backfill_teams_external_id.name
}
