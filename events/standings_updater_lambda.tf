# ============================================================================
# STANDINGS UPDATER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Updates league standings from API-Football
# Schedule: Daily at 1:00 AM UTC
# Coverage: All active leagues with fixtures

# S3 Object Data Source for standings_updater package
data "aws_s3_object" "standings_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/standings_updater.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "standings_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-standings-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-standings-updater-logs"
    },
    var.additional_tags
  )
}

# Standings Updater Lambda Function
resource "aws_lambda_function" "standings_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/standings_updater.zip"
  function_name = "${var.stack_name}-${var.env}-standings-updater"
  description   = "Standings updater job - updates league tables from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.standings_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes (enough for 289 leagues × 1 sec/batch = ~145 seconds)
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.standings_updater.version_id}-${data.aws_s3_object.standings_updater.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-standings-updater"
      PackageETag = data.aws_s3_object.standings_updater.etag
      Purpose     = "batch-standings-update"
      Schedule    = "daily-01:00-utc"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.standings_updater
  ]
}

# EventBridge Schedule: Daily at 1:00 AM UTC
resource "aws_cloudwatch_event_rule" "standings_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-standings-updater-schedule"
  description         = "Trigger standings updater job at 1:00 AM UTC"
  schedule_expression = "cron(0 1 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-standings-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "standings_updater_target" {
  rule      = aws_cloudwatch_event_rule.standings_updater_schedule.name
  target_id = "StandingsUpdaterLambda"
  arn       = aws_lambda_function.standings_updater.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_standings_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.standings_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.standings_updater_schedule.arn
}

# Outputs
output "standings_updater_function_name" {
  description = "Standings updater Lambda function name"
  value       = aws_lambda_function.standings_updater.function_name
}

output "standings_updater_function_arn" {
  description = "Standings updater Lambda function ARN"
  value       = aws_lambda_function.standings_updater.arn
}

output "standings_updater_schedule_rule" {
  description = "Standings updater EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.standings_updater_schedule.name
}
