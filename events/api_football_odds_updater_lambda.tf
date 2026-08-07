# ============================================================================
# API-FOOTBALL ODDS UPDATER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Updates betting odds from API-Football
# Schedule: Every 3 hours
# Coverage: All fixtures with available odds

# S3 Object Data Source for api_football_odds_updater package
data "aws_s3_object" "api_football_odds_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/api_football_odds_updater.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_football_odds_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-api-football-odds-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-api-football-odds-updater-logs"
    },
    var.additional_tags
  )
}

# API-Football Odds Updater Lambda Function
resource "aws_lambda_function" "api_football_odds_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/api_football_odds_updater.zip"
  function_name = "${var.stack_name}-${var.env}-api-football-odds-updater"
  description   = "API-Football odds updater job - updates betting odds from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.api_football_odds_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 240  # 4 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.api_football_odds_updater.version_id}-${data.aws_s3_object.api_football_odds_updater.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-api-football-odds-updater"
      PackageETag = data.aws_s3_object.api_football_odds_updater.etag
      Purpose     = "batch-odds-update"
      Schedule    = "every-3-hours"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.api_football_odds_updater
  ]
}

# EventBridge Schedule: Every 3 hours
resource "aws_cloudwatch_event_rule" "api_football_odds_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-api-football-odds-updater-schedule"
  description         = "Trigger API-Football odds updater job every 3 hours"
  schedule_expression = "cron(0 */3 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-api-football-odds-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "api_football_odds_updater_target" {
  rule      = aws_cloudwatch_event_rule.api_football_odds_updater_schedule.name
  target_id = "ApiFootballOddsUpdaterLambda"
  arn       = aws_lambda_function.api_football_odds_updater.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_api_football_odds_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_football_odds_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.api_football_odds_updater_schedule.arn
}

# Outputs
output "api_football_odds_updater_function_name" {
  description = "API-Football odds updater Lambda function name"
  value       = aws_lambda_function.api_football_odds_updater.function_name
}

output "api_football_odds_updater_function_arn" {
  description = "API-Football odds updater Lambda function ARN"
  value       = aws_lambda_function.api_football_odds_updater.arn
}

output "api_football_odds_updater_schedule_rule" {
  description = "API-Football odds updater EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.api_football_odds_updater_schedule.name
}
