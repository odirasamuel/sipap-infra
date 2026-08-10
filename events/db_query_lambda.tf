# ============================================================================
# DATABASE QUERY LAMBDA (UTILITY)
# ============================================================================
# Manual-invocation utility Lambda for inspecting database contents
# Uses the same S3 deployment package as fixture_updater

# S3 Object Data Source for db_query package
data "aws_s3_object" "db_query" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/fixture_updater.zip"  # Reuse fixture_updater package
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "db_query" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-db-query"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-query-logs"
    },
    var.additional_tags
  )
}

# Database Query Lambda
resource "aws_lambda_function" "db_query" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/fixture_updater.zip"  # Reuse package
  function_name = "${var.stack_name}-${var.env}-db-query"
  description   = "Manual database query utility - invoke to inspect Aurora contents"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.db_query.lambda_handler"
  runtime       = "python3.12"
  timeout       = 120  # Increased from 60s for complex queries
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes using version_id and etag
  source_code_hash = base64encode(sha256("${data.aws_s3_object.db_query.version_id}-${data.aws_s3_object.db_query.etag}"))

  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT           = var.env
      REDIS_URL             = "redis://${data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint}:6379"
      # Aurora database credentials (required for db_query utility)
      AURORA_SECRET_ARN     = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
      AURORA_HOST           = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
      AURORA_PORT           = "5432"
      AURORA_DATABASE       = "sipap_dev"
      AURORA_USER           = "sipap_admin"
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-db-query"
      PackageETag = data.aws_s3_object.db_query.etag
      Purpose     = "database-query-utility"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.db_query
  ]
}

# Output
output "db_query_function_name" {
  description = "Database query Lambda function name"
  value       = aws_lambda_function.db_query.function_name
}

output "db_query_function_arn" {
  description = "Database query Lambda function ARN"
  value       = aws_lambda_function.db_query.arn
}
