# Outputs for WhatsApp Notification DLQ Module

output "retry_queue_url" {
  description = "URL of the WhatsApp notification retry queue"
  value       = aws_sqs_queue.whatsapp_notification_retry.url
}

output "retry_queue_arn" {
  description = "ARN of the WhatsApp notification retry queue"
  value       = aws_sqs_queue.whatsapp_notification_retry.arn
}

output "dlq_url" {
  description = "URL of the WhatsApp notification dead letter queue"
  value       = aws_sqs_queue.whatsapp_notification_dlq.url
}

output "dlq_arn" {
  description = "ARN of the WhatsApp notification dead letter queue"
  value       = aws_sqs_queue.whatsapp_notification_dlq.arn
}

output "lambda_function_name" {
  description = "Name of the notification retry Lambda function"
  value       = aws_lambda_function.notification_retry.function_name
}

output "lambda_function_arn" {
  description = "ARN of the notification retry Lambda function"
  value       = aws_lambda_function.notification_retry.arn
}

output "lambda_role_arn" {
  description = "ARN of the notification retry Lambda IAM role"
  value       = aws_iam_role.notification_retry_lambda.arn
}
