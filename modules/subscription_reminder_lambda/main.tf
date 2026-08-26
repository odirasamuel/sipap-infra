# Subscription Reminder Handler Lambda Module
# Creates a Lambda function that runs on a schedule (EventBridge) to send
# 24-hour pre-expiration reminders to users via WhatsApp

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Lambda function
resource "aws_lambda_function" "subscription_reminder" {
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
  source_code_hash  = var.source_code_hash

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
      POSTGRES_SECRET_ARN = var.postgres_secret_arn
      TWILIO_SECRET_ARN   = var.twilio_secret_arn
      BASE_URL            = var.base_url
      BATCH_SIZE          = tostring(var.batch_size)
    })
  }

  tags = merge(
    {
      Name        = var.function_name
      Environment = var.env
      Service     = "subscription-reminder"
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
      Service     = "subscription-reminder"
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
        Resource = compact([
          var.postgres_secret_arn,
          var.twilio_secret_arn
        ])
      }
    ]
  })
}

# EventBridge rule for scheduled execution (hourly)
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger subscription reminder Lambda every hour"
  schedule_expression = var.schedule_expression

  tags = merge(
    {
      Name        = "${var.function_name}-schedule"
      Environment = var.env
      Service     = "subscription-reminder"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# EventBridge target (Lambda function)
resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "SubscriptionReminderLambda"
  arn       = aws_lambda_function.subscription_reminder.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscription_reminder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.function_name}-logs"
      Environment = var.env
      Service     = "subscription-reminder"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
