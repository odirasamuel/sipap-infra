# ============================================================================
# HISTORICAL BACKFILL PRE-FLIGHT TEST LAMBDA
# ============================================================================
# Lambda function to test backfill pipeline with Premier League (Season 2024)
# before executing full 7-day backfill (61,180 API requests)

# Data sources for secrets
data "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = data.terraform_remote_state.root.outputs.api_keys_secret_arn
}

data "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
}

# Data source for Lambda package
data "aws_s3_object" "backfill_test" {
  bucket = var.lambda_s3_bucket
  key    = "batch-scraper/backfill_test.zip"
}

# CloudWatch log group
resource "aws_cloudwatch_log_group" "backfill_test" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-backfill-test"
  retention_in_days = 7

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-backfill-test-logs"
      Environment = var.env
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Lambda function
resource "aws_lambda_function" "backfill_test" {
  s3_bucket         = data.aws_s3_object.backfill_test.bucket
  s3_key            = data.aws_s3_object.backfill_test.key
  s3_object_version = data.aws_s3_object.backfill_test.version_id

  function_name = "${var.stack_name}-${var.env}-backfill-test"
  handler       = "backfill_test_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900 # 15 minutes (for full season: ~115 API requests + DB operations)
  memory_size   = 1024 # Increased for full backfill
  architectures = ["arm64"]

  # VPC configuration (same as integration test - needs Aurora + Redis access)
  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  # Environment variables
  environment {
    variables = {
      ENVIRONMENT      = var.env
      API_FOOTBALL_KEY = jsondecode(data.aws_secretsmanager_secret_version.api_keys.secret_string)["API_FOOTBALL_KEY"]

      # Aurora credentials (from Secrets Manager)
      AURORA_HOST     = split(":", data.terraform_remote_state.root.outputs.aurora_cluster_endpoint)[0]
      AURORA_PORT     = "5432"
      AURORA_DATABASE = "sipap_dev"
      AURORA_USER     = jsondecode(data.aws_secretsmanager_secret_version.aurora_credentials.secret_string)["username"]
      AURORA_PASSWORD = jsondecode(data.aws_secretsmanager_secret_version.aurora_credentials.secret_string)["password"]

      # Redis configuration
      REDIS_HOST = data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint
      REDIS_PORT = "6379"
    }
  }

  role = module.batch_scraper_lambda_role.role_arn

  depends_on = [
    aws_cloudwatch_log_group.backfill_test,
    module.batch_scraper_lambda_role,
  ]

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-backfill-test"
      Environment = var.env
      ManagedBy   = "Terraform"
      Purpose     = "historical-backfill-pre-flight-test"
    },
    var.additional_tags
  )
}

# Outputs
output "backfill_test_function_name" {
  description = "Backfill test Lambda function name"
  value       = aws_lambda_function.backfill_test.function_name
}

output "backfill_test_function_arn" {
  description = "Backfill test Lambda function ARN"
  value       = aws_lambda_function.backfill_test.arn
}
