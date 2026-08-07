# ============================================================================
# INTEGRATION TEST LAMBDA (PHASE 3 VALIDATION)
# ============================================================================
# Lambda function to run Phase 3 integration tests from within VPC
# Tests Aurora PostgreSQL, Redis cache, and data quality validation
# Invoke manually to validate deployed infrastructure

# S3 Object Data Source for integration test package
data "aws_s3_object" "integration_test" {
  bucket = var.lambda_s3_bucket
  key    = "data-mcp/python_3.12/integration_test.zip"  # Built by sipap-data-mcp workflow
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "integration_test" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-integration-test"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-integration-test-logs"
    },
    var.additional_tags
  )
}

# Integration Test Lambda
resource "aws_lambda_function" "integration_test" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "data-mcp/python_3.12/integration_test.zip"  # Match data source
  function_name = "${var.stack_name}-${var.env}-integration-test"
  description   = "Phase 3 integration tests - validate Aurora/Redis integration and data quality"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "lambda_integration_test.lambda_handler"
  runtime       = "python3.12"
  timeout       = 120  # Longer timeout for running 11 tests
  memory_size   = 512
  architectures = ["arm64"]

  # Track S3 package changes using version_id and etag
  source_code_hash = base64encode(sha256("${data.aws_s3_object.integration_test.version_id}-${data.aws_s3_object.integration_test.etag}"))

  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT           = var.env
      AURORA_HOST           = data.terraform_remote_state.root.outputs.aurora_cluster_endpoint
      AURORA_PORT           = "5432"
      AURORA_DATABASE       = "sipap_dev"
      AURORA_USER           = "sipap_admin"
      AURORA_SECRET_ARN     = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
      REDIS_HOST            = data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint
      REDIS_PORT            = "6379"
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-integration-test"
      PackageETag = data.aws_s3_object.integration_test.etag
      Purpose     = "phase3-integration-testing"
      TestCount   = "11"
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.integration_test
  ]
}

# Output
output "integration_test_function_name" {
  description = "Integration test Lambda function name"
  value       = aws_lambda_function.integration_test.function_name
}

output "integration_test_function_arn" {
  description = "Integration test Lambda function ARN"
  value       = aws_lambda_function.integration_test.arn
}
