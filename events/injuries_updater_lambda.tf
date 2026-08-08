# ============================================================================
# INJURIES UPDATER LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Updates player injuries from API-Football
# Schedule: Hourly
# Coverage: All active fixtures and teams

# S3 Object Data Source for injuries_updater package
data "aws_s3_object" "injuries_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/injuries_updater.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "injuries_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-injuries-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-injuries-updater-logs"
    },
    var.additional_tags
  )
}

# Injuries Updater Lambda Function
resource "aws_lambda_function" "injuries_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/injuries_updater.zip"
  function_name = "${var.stack_name}-${var.env}-injuries-updater"
  description   = "Injuries updater job - updates player injuries from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.injuries_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 180  # 3 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.injuries_updater.version_id}-${data.aws_s3_object.injuries_updater.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-injuries-updater"
      PackageETag = data.aws_s3_object.injuries_updater.etag
      Purpose     = "batch-injuries-update"
      Schedule    = "every-30-minutes"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.injuries_updater
  ]
}

# EventBridge Schedule: Every 30 minutes (increased frequency for breaking injury news)
resource "aws_cloudwatch_event_rule" "injuries_updater_schedule" {
  name                = "${var.stack_name}-${var.env}-injuries-updater-schedule"
  description         = "Trigger injuries updater job every 30 minutes for timely injury updates"
  schedule_expression = "cron(0,30 * * * ? *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-injuries-updater-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "injuries_updater_target" {
  rule      = aws_cloudwatch_event_rule.injuries_updater_schedule.name
  target_id = "InjuriesUpdaterLambda"
  arn       = aws_lambda_function.injuries_updater.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_injuries_updater" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.injuries_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.injuries_updater_schedule.arn
}

# Outputs
output "injuries_updater_function_name" {
  description = "Injuries updater Lambda function name"
  value       = aws_lambda_function.injuries_updater.function_name
}

output "injuries_updater_function_arn" {
  description = "Injuries updater Lambda function ARN"
  value       = aws_lambda_function.injuries_updater.arn
}

output "injuries_updater_schedule_rule" {
  description = "Injuries updater EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.injuries_updater_schedule.name
}
