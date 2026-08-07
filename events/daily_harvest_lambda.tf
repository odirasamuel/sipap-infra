# ============================================================================
# DAILY HARVEST LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Fetches upcoming fixtures from API-Football for next 14 days
# Schedule: Daily at 12:00 AM UTC
# Coverage: 380 competitions globally

# S3 Object Data Source for daily_harvest package
data "aws_s3_object" "daily_harvest" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/daily_harvest.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "daily_harvest" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-daily-harvest"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-daily-harvest-logs"
    },
    var.additional_tags
  )
}

# Daily Harvest Lambda Function
resource "aws_lambda_function" "daily_harvest" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/daily_harvest.zip"
  function_name = "${var.stack_name}-${var.env}-daily-harvest"
  description   = "Daily fixture harvest job - fetches next 14 days of fixtures from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.daily_harvest.version_id}-${data.aws_s3_object.daily_harvest.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-daily-harvest"
      PackageETag = data.aws_s3_object.daily_harvest.etag
      Purpose     = "batch-fixture-harvest"
      Schedule    = "daily-00:00-utc"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.daily_harvest
  ]
}

# EventBridge Schedule: Daily at 12:00 AM UTC
resource "aws_cloudwatch_event_rule" "daily_harvest_schedule" {
  name                = "${var.stack_name}-${var.env}-daily-harvest-schedule"
  description         = "Trigger daily harvest job at 12:00 AM UTC"
  schedule_expression = "cron(0 0 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-daily-harvest-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "daily_harvest_target" {
  rule      = aws_cloudwatch_event_rule.daily_harvest_schedule.name
  target_id = "DailyHarvestLambda"
  arn       = aws_lambda_function.daily_harvest.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_daily_harvest" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_harvest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_harvest_schedule.arn
}

# Outputs
output "daily_harvest_function_name" {
  description = "Daily harvest Lambda function name"
  value       = aws_lambda_function.daily_harvest.function_name
}

output "daily_harvest_function_arn" {
  description = "Daily harvest Lambda function ARN"
  value       = aws_lambda_function.daily_harvest.arn
}

output "daily_harvest_schedule_rule" {
  description = "Daily harvest EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.daily_harvest_schedule.name
}
