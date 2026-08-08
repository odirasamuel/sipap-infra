# ============================================================================
# FIXTURE MANAGER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Unified fixture and score management (replaces daily_harvest + fixture_updater)
#
# Responsibilities:
# 1. Fetch new fixtures (next 30 days) from API-Football
# 2. Update scores for today's matches (live updates)
# 3. Update match status (NS → LIVE → FT)
#
# Schedule: Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
# Coverage: 380 competitions globally
# API Calls: 2 requests per run × 4 times/day = 8 requests/day

# S3 Object Data Source for fixture_manager package
data "aws_s3_object" "fixture_manager" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/fixture_manager.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "fixture_manager" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-fixture-manager"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-manager-logs"
    },
    var.additional_tags
  )
}

# Fixture Manager Lambda Function
resource "aws_lambda_function" "fixture_manager" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/fixture_manager.zip"
  function_name = "${var.stack_name}-${var.env}-fixture-manager"
  description   = "Fixture manager - unified fixture and score management (next 30 days + today's scores)"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.fixture_manager.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.fixture_manager.version_id}-${data.aws_s3_object.fixture_manager.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-fixture-manager"
      PackageETag = data.aws_s3_object.fixture_manager.etag
      Purpose     = "batch-fixture-score-management"
      Schedule    = "every-6-hours-utc"
      Replaces    = "daily-harvest,fixture-updater"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.fixture_manager
  ]
}

# EventBridge Schedule: Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
resource "aws_cloudwatch_event_rule" "fixture_manager_schedule" {
  name                = "${var.stack_name}-${var.env}-fixture-manager-schedule"
  description         = "Trigger fixture manager every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)"
  schedule_expression = "cron(0 0,6,12,18 * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-manager-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "fixture_manager_target" {
  rule      = aws_cloudwatch_event_rule.fixture_manager_schedule.name
  target_id = "FixtureManagerLambda"
  arn       = aws_lambda_function.fixture_manager.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_fixture_manager" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fixture_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fixture_manager_schedule.arn
}

# Outputs
output "fixture_manager_function_name" {
  description = "Fixture manager Lambda function name"
  value       = aws_lambda_function.fixture_manager.function_name
}

output "fixture_manager_function_arn" {
  description = "Fixture manager Lambda function ARN"
  value       = aws_lambda_function.fixture_manager.arn
}

output "fixture_manager_schedule_rule" {
  description = "Fixture manager EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.fixture_manager_schedule.name
}
