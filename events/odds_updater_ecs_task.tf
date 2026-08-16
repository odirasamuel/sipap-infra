# ============================================================================
# COMPREHENSIVE ODDS UPDATER ECS TASK (REPLACES LAMBDA)
# ============================================================================
# Long-running ECS Fargate task for comprehensive odds updates.
# Runs every 3 hours (same schedule as the replaced Lambda).
#
# Advantages over Lambda:
# - No 15-minute timeout limit
# - Can process ALL fixtures comprehensively
# - Better rate limit handling with retries
#
# Triggered via:
# - EventBridge scheduled rule (every 3 hours)
# - Manual: aws ecs run-task --cluster sipap-dev-cluster --task-definition sipap-dev-odds-updater
# - GitHub Actions workflow
#
# Note: ECR repository "odds-updater" is created in main.tf via the ecr module

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for odds updater task (allows container to call AWS APIs)
resource "aws_iam_role" "odds_updater_task_role" {
  name = "${var.stack_name}-${var.env}-odds-updater-task-role"

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
      Name = "${var.stack_name}-${var.env}-odds-updater-task-role"
    },
    var.additional_tags
  )
}

# IAM Policy for odds updater task (Secrets Manager + CloudWatch Logs)
resource "aws_iam_role_policy" "odds_updater_task_policy" {
  name = "odds-updater-permissions"
  role = aws_iam_role.odds_updater_task_role.id

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
          "${aws_cloudwatch_log_group.odds_updater.arn}:*"
        ]
      }
    ]
  })
}

# IAM Role for EventBridge to invoke ECS tasks
resource "aws_iam_role" "eventbridge_ecs_role" {
  name = "${var.stack_name}-${var.env}-eventbridge-odds-updater-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-eventbridge-odds-updater-role"
    },
    var.additional_tags
  )
}

# IAM Policy for EventBridge to run ECS tasks
resource "aws_iam_role_policy" "eventbridge_ecs_policy" {
  name = "eventbridge-run-ecs-task"
  role = aws_iam_role.eventbridge_ecs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.odds_updater.arn,
          # Allow any revision of this task definition
          "${replace(aws_ecs_task_definition.odds_updater.arn, "/:\\d+$/", "")}:*"
        ]
        Condition = {
          ArnLike = {
            "ecs:cluster" = data.terraform_remote_state.root.outputs.ecs_cluster_arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          module.batch_scraper_lambda_role.role_arn,
          aws_iam_role.odds_updater_task_role.arn
        ]
      }
    ]
  })
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "odds_updater" {
  family                   = "${var.stack_name}-${var.env}-odds-updater"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"   # 0.5 vCPU
  memory                   = "1024"  # 1 GB
  execution_role_arn       = module.batch_scraper_lambda_role.role_arn
  task_role_arn            = aws_iam_role.odds_updater_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "odds-updater"
      image = "${data.terraform_remote_state.root.outputs.ecr_repository_urls["odds-updater"]}:latest"

      command = ["python", "-m", "sipap_batch_scraper.jobs.api_football_odds_updater", "--comprehensive"]

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
          name  = "REDIS_HOST"
          value = data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
        },
        {
          name  = "HOURS_AHEAD"
          value = "72"
        }
      ]

      secrets = [
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
          "awslogs-group"         = aws_cloudwatch_log_group.odds_updater.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "odds-updater"
        }
      }

      essential = true
    }
  ])

  tags = merge(
    {
      Name    = "${var.stack_name}-${var.env}-odds-updater"
      Purpose = "comprehensive-odds-update"
    },
    var.additional_tags
  )
}

# ============================================================================
# CLOUDWATCH LOG GROUP
# ============================================================================

resource "aws_cloudwatch_log_group" "odds_updater" {
  name              = "/ecs/${var.stack_name}-${var.env}-odds-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-odds-updater-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# EVENTBRIDGE SCHEDULED RULE (Every 3 Hours)
# ============================================================================

# EventBridge Rule: Every 3 hours (same schedule as replaced Lambda)
# Schedule: 2 AM, 5 AM, 8 AM, 11 AM, 2 PM, 5 PM, 8 PM, 11 PM UTC
resource "aws_cloudwatch_event_rule" "odds_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-odds-updater-schedule"
  description         = "Trigger comprehensive odds updater every 3 hours"
  schedule_expression = "cron(0 2,5,8,11,14,17,20,23 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-odds-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target: ECS Task
resource "aws_cloudwatch_event_target" "odds_updater_target" {
  rule      = aws_cloudwatch_event_rule.odds_updater_schedule.name
  target_id = "OddsUpdaterECSTask"
  arn       = data.terraform_remote_state.root.outputs.ecs_cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs_role.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.odds_updater.arn
    task_count          = 1
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = data.terraform_remote_state.root.outputs.private_subnet_ids
      security_groups  = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
      assign_public_ip = false
    }
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "odds_updater_repository_url" {
  description = "ECR repository URL for odds updater container"
  value       = data.terraform_remote_state.root.outputs.ecr_repository_urls["odds-updater"]
}

output "odds_updater_task_definition_arn" {
  description = "ECS task definition ARN for comprehensive odds updater"
  value       = aws_ecs_task_definition.odds_updater.arn
}

output "odds_updater_task_definition_family" {
  description = "ECS task definition family name"
  value       = aws_ecs_task_definition.odds_updater.family
}

output "odds_updater_schedule_rule" {
  description = "EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.odds_updater_schedule.name
}

output "odds_updater_schedule_expression" {
  description = "EventBridge schedule expression"
  value       = aws_cloudwatch_event_rule.odds_updater_schedule.schedule_expression
}
