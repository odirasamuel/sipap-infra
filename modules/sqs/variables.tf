# Core naming variables
variable "stack_name" {
  description = "The name of the stack"
  type        = string
}

variable "env" {
  description = "The environment"
  type        = string
}

# Role ARNs for access policies
variable "sqs_role_arn" {
  description = "ARN of the SQS role that can send messages to the queues"
  type        = string
}

variable "orchestrator_role_arn" {
  description = "ARN of the orchestrator/sentinel role that can receive messages from the queues"
  type        = string
  default     = null
}

# Queue configuration
variable "max_receive_count" {
  description = "Maximum number of receives before message is sent to DLQ"
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for main queue in seconds. Must be longer than longest workflow duration (default: 3600 = 60 minutes)"
  type        = number
  default     = 3600
  validation {
    condition     = var.visibility_timeout_seconds >= 60 && var.visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 60 seconds and 43200 seconds (12 hours)"
  }
}

variable "dlq_visibility_timeout_seconds" {
  description = "Visibility timeout for dead letter queue in seconds"
  type        = number
  default     = 60
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}