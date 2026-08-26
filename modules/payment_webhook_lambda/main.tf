# Payment Webhook Handler Lambda Module
# Creates a Lambda function for handling Stripe, Paystack, and Flutterwave payment webhooks
# Supports both local and S3-based deployment (consistent with MCP Lambda pattern)

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Validation: Ensure required variables are provided based on deployment method
locals {
  validate_local_deployment = (
    !var.use_s3_deployment && var.function_source_dir == null
    ? tobool("ERROR: function_source_dir is required when use_s3_deployment is false")
    : true
  )

  validate_s3_deployment = (
    var.use_s3_deployment && (var.s3_bucket == null || var.s3_key == null)
    ? tobool("ERROR: s3_bucket and s3_key are required when use_s3_deployment is true")
    : true
  )
}

# Archive Lambda function from source directory (only for local deployment)
data "archive_file" "function_code" {
  count = var.use_s3_deployment ? 0 : 1

  type        = "zip"
  source_dir  = var.function_source_dir
  output_path = "${path.module}/../../zipped/${var.function_name}.zip"
}

# Lambda function
resource "aws_lambda_function" "payment_webhook" {
  function_name = var.function_name
  description   = var.function_description
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  handler       = var.lambda_handler
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Conditional deployment source - use S3 or local archive
  filename         = var.use_s3_deployment ? null : data.archive_file.function_code[0].output_path
  source_code_hash = var.use_s3_deployment ? var.s3_source_code_hash : data.archive_file.function_code[0].output_base64sha256

  s3_bucket         = var.use_s3_deployment ? var.s3_bucket : null
  s3_key            = var.use_s3_deployment ? var.s3_key : null
  s3_object_version = var.use_s3_deployment ? var.s3_object_version : null

  role = aws_iam_role.lambda_execution.arn

  # VPC configuration for Aurora access
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = var.security_group_ids
  }

  # Lambda layers (if any)
  layers = var.layer_arns

  environment {
    variables = merge(var.environment_variables, {
      POSTGRES_SECRET_ARN              = var.postgres_secret_arn
      STRIPE_WEBHOOK_SECRET            = var.stripe_webhook_secret
      PAYSTACK_SECRET_KEY              = var.paystack_secret_key
      FLUTTERWAVE_WEBHOOK_SECRET       = var.flutterwave_webhook_secret
      TWILIO_SECRET_ARN                = var.twilio_secret_arn
      WHATSAPP_NOTIFICATION_QUEUE_URL  = var.notification_queue_url
    })
  }

  tags = merge(
    {
      Name        = var.function_name
      Environment = var.env
      Service     = "payment-webhook"
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
      Service     = "payment-webhook"
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

# VPC access policy (for Aurora)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Secrets Manager and SQS access
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${var.function_name}-custom-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "SecretsManagerAccess"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue"
          ]
          Resource = compact([
            var.postgres_secret_arn,
            var.twilio_secret_arn
          ])
        }
      ],
      # Conditionally add SQS permission if notification queue is configured
      var.notification_queue_arn != "" ? [
        {
          Sid    = "SQSNotificationQueueAccess"
          Effect = "Allow"
          Action = [
            "sqs:SendMessage"
          ]
          Resource = var.notification_queue_arn
        }
      ] : []
    )
  })
}

# API Gateway permission to invoke Lambda (for webhook endpoint)
resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_api_gateway_permission ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payment_webhook.function_name
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
      Service     = "payment-webhook"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
