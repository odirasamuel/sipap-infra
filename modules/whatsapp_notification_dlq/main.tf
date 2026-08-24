# WhatsApp Notification Retry Queue Module
#
# This module creates an SQS queue for retrying failed WhatsApp notifications
# after payment confirmations. Failed notifications are retried up to 3 times
# with a 5-minute delay before being moved to the dead letter queue.
#
# Architecture:
#   Payment Webhook Lambda ---> Retry Queue ---> Notification Retry Lambda
#                                    |
#                            (after 3 failures)
#                                    |
#                                    v
#                               Dead Letter Queue

# ==============================================================================
# Data Sources
# ==============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# Dead Letter Queue (permanent failures)
# ==============================================================================

resource "aws_sqs_queue" "whatsapp_notification_dlq" {
  name                       = "${var.stack_name}-${var.env}-whatsapp-notification-dlq"
  message_retention_seconds  = 1209600  # 14 days

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-notification-dlq"
      Environment = var.env
      Service     = "whatsapp-notification"
      Purpose     = "dead-letter-queue"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# Retry Queue (with exponential backoff via delay)
# ==============================================================================

resource "aws_sqs_queue" "whatsapp_notification_retry" {
  name                       = "${var.stack_name}-${var.env}-whatsapp-notification-retry"
  delay_seconds              = 300  # 5 minute delay before first retry
  max_message_size           = 2048
  message_retention_seconds  = 86400  # 24 hours
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 60  # Allow 1 minute for Lambda execution

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.whatsapp_notification_dlq.arn
    maxReceiveCount     = 3  # Max 3 retries before moving to DLQ
  })

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-notification-retry"
      Environment = var.env
      Service     = "whatsapp-notification"
      Purpose     = "retry-queue"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# Queue Policies
# ==============================================================================

resource "aws_sqs_queue_policy" "retry_queue_policy" {
  queue_url = aws_sqs_queue.whatsapp_notification_retry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "WhatsAppNotificationRetryPolicy"
    Statement = concat(
      [
        {
          Sid    = "AllowAccountAccess"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "SQS:*"
          Resource = aws_sqs_queue.whatsapp_notification_retry.arn
        }
      ],
      # Conditionally add specific role permission if provided
      var.payment_webhook_role_arn != "" ? [
        {
          Sid    = "AllowPaymentWebhookSend"
          Effect = "Allow"
          Principal = {
            AWS = var.payment_webhook_role_arn
          }
          Action = [
            "SQS:SendMessage"
          ]
          Resource = aws_sqs_queue.whatsapp_notification_retry.arn
        }
      ] : []
    )
  })
}

resource "aws_sqs_queue_policy" "dlq_policy" {
  queue_url = aws_sqs_queue.whatsapp_notification_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "WhatsAppNotificationDLQPolicy"
    Statement = [
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "SQS:*"
        Resource = aws_sqs_queue.whatsapp_notification_dlq.arn
      }
    ]
  })
}

# Redrive allow policy for DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq_redrive_policy" {
  queue_url = aws_sqs_queue.whatsapp_notification_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.whatsapp_notification_retry.arn]
  })
}

# ==============================================================================
# Lambda Function for Notification Retry
# ==============================================================================

# IAM Role for Notification Retry Lambda
resource "aws_iam_role" "notification_retry_lambda" {
  name = "${var.stack_name}-${var.env}-notification-retry-lambda-role"

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
      Name        = "${var.stack_name}-${var.env}-notification-retry-lambda-role"
      Environment = var.env
      Service     = "notification-retry"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "notification_retry_lambda_policy" {
  name = "${var.stack_name}-${var.env}-notification-retry-lambda-policy"
  role = aws_iam_role.notification_retry_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.whatsapp_notification_retry.arn
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.twilio_secret_arn
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "notification_retry" {
  function_name = "${var.stack_name}-${var.env}-notification-retry"
  role          = aws_iam_role.notification_retry_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 128

  s3_bucket = var.lambda_s3_bucket
  s3_key    = var.lambda_s3_key

  environment {
    variables = {
      TWILIO_SECRET_ARN = var.twilio_secret_arn
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-notification-retry"
      Environment = var.env
      Service     = "notification-retry"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "notification_retry_lambda" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-notification-retry"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-notification-retry-logs"
      Environment = var.env
      Service     = "notification-retry"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# SQS Event Source Mapping for Lambda
resource "aws_lambda_event_source_mapping" "notification_retry" {
  event_source_arn = aws_sqs_queue.whatsapp_notification_retry.arn
  function_name    = aws_lambda_function.notification_retry.arn
  batch_size       = 1  # Process one notification at a time

  enabled = true
}
