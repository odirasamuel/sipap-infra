# ============================================================================
# H2H FETCHER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Fetches head-to-head stats from API-Football
# Schedule: Daily at 3:00 AM UTC
# Coverage: All upcoming fixtures (fetches H2H for match pairs)

# S3 Object Data Source for h2h_fetcher package
data "aws_s3_object" "h2h_fetcher" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/h2h_fetcher.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "h2h_fetcher" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-h2h-fetcher"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-h2h-fetcher-logs"
    },
    var.additional_tags
  )
}

# H2H Fetcher Lambda Function
resource "aws_lambda_function" "h2h_fetcher" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/h2h_fetcher.zip"
  function_name = "${var.stack_name}-${var.env}-h2h-fetcher"
  description   = "H2H fetcher job - fetches head-to-head stats from API-Football for upcoming fixtures"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.h2h_fetcher.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes (processes H2H for all upcoming fixtures)
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.h2h_fetcher.version_id}-${data.aws_s3_object.h2h_fetcher.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-h2h-fetcher"
      PackageETag = data.aws_s3_object.h2h_fetcher.etag
      Purpose     = "batch-h2h-fetch"
      Schedule    = "daily-03:00-utc"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.h2h_fetcher
  ]
}

# EventBridge Schedule: Daily at 3:00 AM UTC
resource "aws_cloudwatch_event_rule" "h2h_fetcher_schedule" {
  name                = "${var.stack_name}-${var.env}-h2h-fetcher-schedule"
  description         = "Trigger H2H fetcher job daily at 3:00 AM UTC"
  schedule_expression = "cron(0 3 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-h2h-fetcher-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "h2h_fetcher_target" {
  rule      = aws_cloudwatch_event_rule.h2h_fetcher_schedule.name
  target_id = "H2HFetcherLambda"
  arn       = aws_lambda_function.h2h_fetcher.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_h2h_fetcher" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.h2h_fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.h2h_fetcher_schedule.arn
}

# Outputs
output "h2h_fetcher_function_name" {
  description = "H2H fetcher Lambda function name"
  value       = aws_lambda_function.h2h_fetcher.function_name
}

output "h2h_fetcher_function_arn" {
  description = "H2H fetcher Lambda function ARN"
  value       = aws_lambda_function.h2h_fetcher.arn
}

output "h2h_fetcher_schedule_rule" {
  description = "H2H fetcher EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.h2h_fetcher_schedule.name
}
