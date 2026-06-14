# Description: This module creates SQS FIFO queues for Sentinel event processing with dead letter queue configuration

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Dead Letter Queue - Must be created first
resource "aws_sqs_queue" "sentinel_events_dlq" {
  name                        = "${var.stack_name}-events-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  fifo_throughput_limit       = "perMessageGroupId"
  deduplication_scope         = "messageGroup"

  # Configuration
  visibility_timeout_seconds = 60      # 1 minute
  max_message_size           = 262144  # 256 KB
  message_retention_seconds  = 1209600 # 14 days (default)
  receive_wait_time_seconds  = 0       # Default for DLQ

  tags = merge({
    Name  = "${var.stack_name}-${var.env}-sentinel-events-dlq.fifo"
    Owner = "sentinel-automation"
  }, var.additional_tags)
}

# Main FIFO Queue with DLQ configuration
resource "aws_sqs_queue" "sentinel_events" {
  name                        = "${var.stack_name}-events.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  fifo_throughput_limit       = "perMessageGroupId"
  deduplication_scope         = "messageGroup"

  # Configuration
  visibility_timeout_seconds = 1200    # 20 minutes
  max_message_size           = 262144  # 256 KB
  message_retention_seconds  = 1209600 # 14 days (default)
  receive_wait_time_seconds  = 20      # 20 seconds

  # Dead Letter Queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sentinel_events_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge({
    Name  = "${var.stack_name}-${var.env}-sentinel-events.fifo"
    Owner = "sentinel-automation"
  }, var.additional_tags)
}

# Access Policy for Main Queue
resource "aws_sqs_queue_policy" "sentinel_events_policy" {
  queue_url = aws_sqs_queue.sentinel_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "__default_policy_ID"
    Statement = concat(
      [
        {
          Sid    = "__owner_statement"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "SQS:*"
          Resource = aws_sqs_queue.sentinel_events.arn
        },
        {
          Sid    = "__sender_statement"
          Effect = "Allow"
          Principal = {
            AWS = var.sqs_role_arn
          }
          Action = [
            "SQS:SendMessage"
          ]
          Resource = aws_sqs_queue.sentinel_events.arn
        }
      ],
      # Conditionally add receiver statement only if orchestrator_role_arn is provided
      var.orchestrator_role_arn != null ? [
        {
          Sid    = "__receiver_statement"
          Effect = "Allow"
          Principal = {
            AWS = var.orchestrator_role_arn
          }
          Action = [
            "SQS:ChangeMessageVisibility",
            "SQS:DeleteMessage",
            "SQS:ReceiveMessage"
          ]
          Resource = aws_sqs_queue.sentinel_events.arn
        }
      ] : []
    )
  })
}

# Access Policy for Dead Letter Queue
resource "aws_sqs_queue_policy" "sentinel_events_dlq_policy" {
  queue_url = aws_sqs_queue.sentinel_events_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "__default_policy_ID"
    Statement = concat(
      [
        {
          Sid    = "__owner_statement"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "SQS:*"
          Resource = aws_sqs_queue.sentinel_events_dlq.arn
        },
        {
          Sid    = "__sender_statement"
          Effect = "Allow"
          Principal = {
            AWS = var.sqs_role_arn
          }
          Action = [
            "SQS:SendMessage"
          ]
          Resource = aws_sqs_queue.sentinel_events_dlq.arn
        }
      ],
      # Conditionally add receiver statement only if orchestrator_role_arn is provided
      var.orchestrator_role_arn != null ? [
        {
          Sid    = "__receiver_statement"
          Effect = "Allow"
          Principal = {
            AWS = var.orchestrator_role_arn
          }
          Action = [
            "SQS:ChangeMessageVisibility",
            "SQS:DeleteMessage",
            "SQS:ReceiveMessage"
          ]
          Resource = aws_sqs_queue.sentinel_events_dlq.arn
        }
      ] : []
    )
  })
}

# Redrive Allow Policy for Dead Letter Queue
resource "aws_sqs_queue_redrive_allow_policy" "sentinel_events_dlq_redrive_policy" {
  queue_url = aws_sqs_queue.sentinel_events_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.sentinel_events.arn]
  })
}