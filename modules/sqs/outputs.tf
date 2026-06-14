# Main Queue Outputs
output "sentinel_events_queue_arn" {
  description = "ARN of the Sentinel Events FIFO queue"
  value       = aws_sqs_queue.sentinel_events.arn
}

output "sentinel_events_queue_url" {
  description = "URL of the Sentinel Events FIFO queue"
  value       = aws_sqs_queue.sentinel_events.url
}

output "sentinel_events_queue_name" {
  description = "Name of the Sentinel Events FIFO queue"
  value       = aws_sqs_queue.sentinel_events.name
}

# Dead Letter Queue Outputs
output "sentinel_events_dlq_arn" {
  description = "ARN of the Sentinel Events Dead Letter FIFO queue"
  value       = aws_sqs_queue.sentinel_events_dlq.arn
}

output "sentinel_events_dlq_url" {
  description = "URL of the Sentinel Events Dead Letter FIFO queue"
  value       = aws_sqs_queue.sentinel_events_dlq.url
}

output "sentinel_events_dlq_name" {
  description = "Name of the Sentinel Events Dead Letter FIFO queue"
  value       = aws_sqs_queue.sentinel_events_dlq.name
}

# Combined outputs for easy reference
output "queue_arns" {
  description = "Map of all queue ARNs"
  value = {
    main_queue = aws_sqs_queue.sentinel_events.arn
    dlq        = aws_sqs_queue.sentinel_events_dlq.arn
  }
}

output "queue_urls" {
  description = "Map of all queue URLs"
  value = {
    main_queue = aws_sqs_queue.sentinel_events.url
    dlq        = aws_sqs_queue.sentinel_events_dlq.url
  }
}