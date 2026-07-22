# WhatsApp Message Queue Module
# FIFO queues for asynchronous WhatsApp message processing with DLQ

# Dead Letter Queue - Must be created first
resource "aws_sqs_queue" "whatsapp_messages_dlq" {
  name                        = "${var.stack_name}-${var.env}-whatsapp-messages-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true

  # Short visibility timeout for DLQ (messages are already failed)
  visibility_timeout_seconds = var.dlq_visibility_timeout_seconds

  # Same retention as main queue for forensics
  message_retention_seconds = var.message_retention_seconds

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-messages-dlq"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Purpose     = "dead-letter-queue"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Main WhatsApp Message Queue (FIFO)
# Messages are processed by ECS orchestrator using long polling pattern
resource "aws_sqs_queue" "whatsapp_messages" {
  name                        = "${var.stack_name}-${var.env}-whatsapp-messages.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  fifo_throughput_limit       = "perMessageGroupId"
  deduplication_scope         = "messageGroup"

  # Visibility timeout must be longer than longest workflow
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # 256 KB max message size (standard SQS limit)
  max_message_size = var.max_message_size

  # Message retention for debugging and replay capability
  message_retention_seconds = var.message_retention_seconds

  # Long polling - reduces API calls by ~95%
  receive_wait_time_seconds = var.receive_wait_time_seconds

  # Redrive policy - send to DLQ after max receive count
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.whatsapp_messages_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-messages"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# SQS Queue Policy - Allows API Gateway service principal to send messages
resource "aws_sqs_queue_policy" "whatsapp_messages" {
  queue_url = aws_sqs_queue.whatsapp_messages.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAPIGatewaySendMessage"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action   = "SQS:SendMessage"
        Resource = aws_sqs_queue.whatsapp_messages.arn
      }
    ]
  })
}
