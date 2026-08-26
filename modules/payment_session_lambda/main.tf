# Payment Session Handler Lambda Module
# Creates a Lambda function for creating Flutterwave payment sessions
# This Lambda does NOT need VPC access - it only calls external Flutterwave API

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Lambda function
resource "aws_lambda_function" "payment_session" {
  function_name = var.function_name
  description   = var.function_description
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  handler       = var.lambda_handler
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # S3-based deployment
  s3_bucket         = var.s3_bucket
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version

  role = aws_iam_role.lambda_execution.arn

  # Lambda layers (if any)
  layers = var.layer_arns

  environment {
    variables = merge(var.environment_variables, {
      FLUTTERWAVE_SECRET_ARN = var.flutterwave_secret_arn
      REDIRECT_URL           = var.redirect_url
    })
  }

  tags = merge(
    {
      Name        = var.function_name
      Environment = var.env
      Service     = "payment-session"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name        = "${var.function_name}-execution-role"
      Environment = var.env
      Service     = "payment-session"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Basic Lambda execution policy (CloudWatch logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Secrets Manager access
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${var.function_name}-custom-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.flutterwave_secret_arn
        ]
      }
    ]
  })
}

# API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_api_gateway_permission ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payment_session.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.function_name}-logs"
      Environment = var.env
      Service     = "payment-session"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
