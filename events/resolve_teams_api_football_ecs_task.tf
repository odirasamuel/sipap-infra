# ============================================================================
# RESOLVE TEAMS VIA API-FOOTBALL ECS TASK
# ============================================================================
# On-demand ECS Fargate task to resolve teams external_id via API-Football.
#
# This job searches API-Football for teams that don't have external_id set,
# finds matches, and updates the database.
#
# Environment variables:
# - DRY_RUN: Set to "true" to report without making changes
#
# Triggered via:
# - GitHub Actions workflow (workflow_dispatch)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster \
#           --task-definition sipap-dev-resolve-teams-api-football \
#           --launch-type FARGATE \
#           --network-configuration "awsvpcConfiguration={...}"

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "resolve_teams_api_football" {
  name              = "/ecs/${var.stack_name}-${var.env}-resolve-teams-api-football"
  retention_in_days = 14

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-resolve-teams-api-football-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "resolve_teams_api_football" {
  family                   = "${var.stack_name}-${var.env}-resolve-teams-api-football"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  # Reuse the backfill task role since it has the same permissions needed
  task_role_arn            = aws_iam_role.backfill_teams_external_id_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "resolve-teams-api-football"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["db-query"]}:latest"

      # Override entrypoint to run resolve_teams_via_api_football
      entryPoint = ["python", "-m", "sipap_batch_scraper.jobs.resolve_teams_via_api_football", "--ecs"]
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
          "awslogs-group"         = aws_cloudwatch_log_group.resolve_teams_api_football.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "resolve-teams-api-football"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-resolve-teams-api-football"
    },
    var.additional_tags
  )
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "resolve_teams_api_football_task_definition_arn" {
  description = "ARN of the resolve-teams-api-football ECS task definition"
  value       = aws_ecs_task_definition.resolve_teams_api_football.arn
}

output "resolve_teams_api_football_log_group" {
  description = "CloudWatch log group for resolve-teams-api-football"
  value       = aws_cloudwatch_log_group.resolve_teams_api_football.name
}
