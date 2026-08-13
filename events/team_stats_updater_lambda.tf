# ============================================================================
# TEAM STATS UPDATER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Updates team statistics from API-Football
# Schedule: Daily at 2:00 AM UTC
# Coverage: All teams in active leagues

# S3 Object Data Source for team_stats_updater package
data "aws_s3_object" "team_stats_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/team_stats_updater.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "team_stats_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-team-stats-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-team-stats-updater-logs"
    },
    var.additional_tags
  )
}

# Team Stats Updater Lambda Function
resource "aws_lambda_function" "team_stats_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/team_stats_updater.zip"
  function_name = "${var.stack_name}-${var.env}-team-stats-updater"
  description   = "Team stats updater job - updates team statistics from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.team_stats_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 600  # 10 minutes (max for Lambda in VPC with lots of API calls)
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.team_stats_updater.version_id}-${data.aws_s3_object.team_stats_updater.etag}"))

  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT           = var.env
      API_KEYS_SECRET_ARN   = data.terraform_remote_state.root.outputs.api_keys_secret_arn
      AURORA_SECRET_ARN     = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
      AURORA_HOST           = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
      AURORA_PORT           = "5432"
      AURORA_DATABASE       = "sipap_dev"
      AURORA_USER           = "sipap_admin"
      REDIS_HOST            = data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint
      REDIS_PORT            = "6379"
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-team-stats-updater"
      PackageETag = data.aws_s3_object.team_stats_updater.etag
      Purpose     = "batch-team-stats-update"
      Schedule    = "daily-02:00-utc"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.team_stats_updater
  ]
}

# EventBridge Schedule: Daily at 2:00 AM UTC
resource "aws_cloudwatch_event_rule" "team_stats_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-team-stats-updater-schedule"
  description         = "Trigger team stats updater job at 2:00 AM UTC"
  schedule_expression = "cron(0 2 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-team-stats-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "team_stats_updater_target" {
  rule      = aws_cloudwatch_event_rule.team_stats_updater_schedule.name
  target_id = "TeamStatsUpdaterLambda"
  arn       = aws_lambda_function.team_stats_updater.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_team_stats_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.team_stats_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.team_stats_updater_schedule.arn
}

# Outputs
output "team_stats_updater_function_name" {
  description = "Team stats updater Lambda function name"
  value       = aws_lambda_function.team_stats_updater.function_name
}

output "team_stats_updater_function_arn" {
  description = "Team stats updater Lambda function ARN"
  value       = aws_lambda_function.team_stats_updater.arn
}

output "team_stats_updater_schedule_rule" {
  description = "Team stats updater EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.team_stats_updater_schedule.name
}
