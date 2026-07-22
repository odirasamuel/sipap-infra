# WhatsApp SQS Module Outputs

output "queue_url" {
  description = "URL of the WhatsApp messages SQS queue"
  value       = aws_sqs_queue.whatsapp_messages.url
}

output "queue_arn" {
  description = "ARN of the WhatsApp messages SQS queue"
  value       = aws_sqs_queue.whatsapp_messages.arn
}

output "queue_name" {
  description = "Name of the WhatsApp messages SQS queue"
  value       = aws_sqs_queue.whatsapp_messages.name
}

output "dlq_url" {
  description = "URL of the WhatsApp messages DLQ"
  value       = aws_sqs_queue.whatsapp_messages_dlq.url
}

output "dlq_arn" {
  description = "ARN of the WhatsApp messages DLQ"
  value       = aws_sqs_queue.whatsapp_messages_dlq.arn
}

output "dlq_name" {
  description = "Name of the WhatsApp messages DLQ"
  value       = aws_sqs_queue.whatsapp_messages_dlq.name
}
