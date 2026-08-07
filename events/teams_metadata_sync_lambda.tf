# ============================================================================
# TEAMS METADATA SYNC LAMBDA (SCHEDULED BATCH JOB)
# ============================================================================
# Syncs team metadata (logos, venues, etc.) from API-Football
# Schedule: Weekly on Sunday at 3:00 AM UTC
# Coverage: All teams in database

# S3 Object Data Source for teams_metadata_sync package
data "aws_s3_object" "teams_metadata_sync" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/teams_metadata_sync.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "teams_metadata_sync" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-teams-metadata-sync"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-teams-metadata-sync-logs"
    },
    var.additional_tags
  )
}

# Teams Metadata Sync Lambda Function
resource "aws_lambda_function" "teams_metadata_sync" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/teams_metadata_sync.zip"
  function_name = "${var.stack_name}-${var.env}-teams-metadata-sync"
  description   = "Teams metadata sync job - syncs team logos, venues from API-Football"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.teams_metadata_sync.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 minutes
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes
  source_code_hash = base64encode(sha256("${data.aws_s3_object.teams_metadata_sync.version_id}-${data.aws_s3_object.teams_metadata_sync.etag}"))

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
      Name        = "${var.stack_name}-${var.env}-teams-metadata-sync"
      PackageETag = data.aws_s3_object.teams_metadata_sync.etag
      Purpose     = "batch-teams-metadata-sync"
      Schedule    = "weekly-sunday-03:00-utc"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.teams_metadata_sync
  ]
}

# EventBridge Schedule: Weekly on Sunday at 3:00 AM UTC
resource "aws_cloudwatch_event_rule" "teams_metadata_sync_schedule" {
  name                = "${var.stack_name}-${var.env}-teams-metadata-sync-schedule"
  description         = "Trigger teams metadata sync job weekly on Sunday at 3:00 AM UTC"
  schedule_expression = "cron(0 3 ? * SUN *)"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-teams-metadata-sync-schedule"
    },
    var.additional_tags
  )
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "teams_metadata_sync_target" {
  rule      = aws_cloudwatch_event_rule.teams_metadata_sync_schedule.name
  target_id = "TeamsMetadataSyncLambda"
  arn       = aws_lambda_function.teams_metadata_sync.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_teams_metadata_sync" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.teams_metadata_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.teams_metadata_sync_schedule.arn
}

# Outputs
output "teams_metadata_sync_function_name" {
  description = "Teams metadata sync Lambda function name"
  value       = aws_lambda_function.teams_metadata_sync.function_name
}

output "teams_metadata_sync_function_arn" {
  description = "Teams metadata sync Lambda function ARN"
  value       = aws_lambda_function.teams_metadata_sync.arn
}

output "teams_metadata_sync_schedule_rule" {
  description = "Teams metadata sync EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.teams_metadata_sync_schedule.name
}
