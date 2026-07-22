# WhatsApp SQS Module Variables

variable "stack_name" {
  description = "Stack name (e.g., sipap)"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
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

variable "max_message_size" {
  description = "Maximum message size in bytes (default: 262144 = 256 KB)"
  type        = number
  default     = 262144
  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 262144
    error_message = "Max message size must be between 1024 bytes and 262144 bytes (256 KB)"
  }
}

variable "message_retention_seconds" {
  description = "Message retention period in seconds (default: 1209600 = 14 days)"
  type        = number
  default     = 1209600
  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 seconds and 1209600 seconds (14 days)"
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time in seconds (default: 20 seconds, reduces API calls by ~95%)"
  type        = number
  default     = 20
  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "Receive wait time must be between 0 and 20 seconds"
  }
}

variable "max_receive_count" {
  description = "Maximum number of receives before message is sent to DLQ (default: 30)"
  type        = number
  default     = 30
  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
