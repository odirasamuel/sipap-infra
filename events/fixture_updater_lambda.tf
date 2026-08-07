# ============================================================================
# FIXTURE UPDATER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Updates fixture details and statuses from API-Football
# Schedule: Every 6 hours
# Coverage: All active fixtures

# S3 Object Data Source for fixture_updater package
data "aws_s3_object" "fixture_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/fixture_updater.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "fixture_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-fixture-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-updater-logs"
    },
    var.additional_tags
  )
}

# Fixture Updater Lambda Function
resource "aws_lambda_function" "fixture_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/fixture_updater.zip"
  function_name = "${var.stack_name}-${var.env}-fixture-updater"
  description   = "Fixture updater job - updates fixture details and statuses from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 240  # 4 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.fixture_updater.version_id}-${data.aws_s3_object.fixture_updater.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-fixture-updater"
      PackageETag = data.aws_s3_object.fixture_updater.etag
      Purpose     = "batch-fixture-update"
      Schedule    = "every-6-hours"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.fixture_updater
  ]
}

# EventBridge Schedule: Every 6 hours
resource "aws_cloudwatch_event_rule" "fixture_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-fixture-updater-schedule"
  description         = "Trigger fixture updater job every 6 hours"
  schedule_expression = "cron(0 */6 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "fixture_updater_target" {
  rule      = aws_cloudwatch_event_rule.fixture_updater_schedule.name
  target_id = "FixtureUpdaterLambda"
  arn       = aws_lambda_function.fixture_updater.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_fixture_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fixture_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fixture_updater_schedule.arn
}

# Outputs
output "fixture_updater_function_name" {
  description = "Fixture updater Lambda function name"
  value       = aws_lambda_function.fixture_updater.function_name
}

output "fixture_updater_function_arn" {
  description = "Fixture updater Lambda function ARN"
  value       = aws_lambda_function.fixture_updater.arn
}

output "fixture_updater_schedule_rule" {
  description = "Fixture updater EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.fixture_updater_schedule.name
}
