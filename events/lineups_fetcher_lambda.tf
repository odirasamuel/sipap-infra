# ============================================================================
# LINEUPS FETCHER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Fetches starting lineups from API-Football for upcoming matches
# Schedule: Hourly
# Coverage: Matches within 24 hours

# S3 Object Data Source for lineups_fetcher package
data "aws_s3_object" "lineups_fetcher" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/lineups_fetcher.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lineups_fetcher" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-lineups-fetcher"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-lineups-fetcher-logs"
    },
    var.additional_tags
  )
}

# Lineups Fetcher Lambda Function
resource "aws_lambda_function" "lineups_fetcher" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/lineups_fetcher.zip"
  function_name = "${var.stack_name}-${var.env}-lineups-fetcher"
  description   = "Lineups fetcher job - fetches starting lineups from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.lineups_fetcher.lambda_handler"
  runtime       = "python3.12"
  timeout       = 180  # 3 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.lineups_fetcher.version_id}-${data.aws_s3_object.lineups_fetcher.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-lineups-fetcher"
      PackageETag = data.aws_s3_object.lineups_fetcher.etag
      Purpose     = "batch-lineups-fetch"
      Schedule    = "every-30-minutes"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.lineups_fetcher
  ]
}

# EventBridge Schedule: Every 30 minutes (increased frequency for lineup confirmations)
resource "aws_cloudwatch_event_rule" "lineups_fetcher_schedule" {
  name                = "${var.stack_name}-${var.env}-lineups-fetcher-schedule"
  description         = "Trigger lineups fetcher job every 30 minutes for timely lineup confirmations"
  schedule_expression = "cron(0,30 * * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-lineups-fetcher-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "lineups_fetcher_target" {
  rule      = aws_cloudwatch_event_rule.lineups_fetcher_schedule.name
  target_id = "LineupsFetcherLambda"
  arn       = aws_lambda_function.lineups_fetcher.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_lineups_fetcher" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lineups_fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lineups_fetcher_schedule.arn
}

# Outputs
output "lineups_fetcher_function_name" {
  description = "Lineups fetcher Lambda function name"
  value       = aws_lambda_function.lineups_fetcher.function_name
}

output "lineups_fetcher_function_arn" {
  description = "Lineups fetcher Lambda function ARN"
  value       = aws_lambda_function.lineups_fetcher.arn
}

output "lineups_fetcher_schedule_rule" {
  description = "Lineups fetcher EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.lineups_fetcher_schedule.name
}
