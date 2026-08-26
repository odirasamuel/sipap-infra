# Subscription Reminder Lambda Module Variables

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "function_description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "Subscription expiration reminder handler - sends 24-hour pre-expiration WhatsApp reminders"
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# ==============================================================================
# S3 Deployment Configuration
# ==============================================================================

variable "s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "s3_key" {
  description = "S3 key (path) to the Lambda deployment package"
  type        = string
}

variable "s3_object_version" {
  description = "Specific S3 object version to deploy (optional, leave null to use latest)"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64-encoded hash of the S3 package (triggers redeployment on change)"
  type        = string
  default     = null
}

# ==============================================================================
# Lambda Runtime Configuration
# ==============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.13"
}

variable "lambda_architectures" {
  description = "Lambda architectures"
  type        = list(string)
  default     = ["x86_64"]
}

variable "lambda_handler" {
  description = "Lambda handler function"
  type        = string
  default     = "handler.handler"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "layer_arns" {
  description = "List of Lambda layer ARNs to attach"
  type        = list(string)
  default     = []
}

# ==============================================================================
# VPC Configuration
# ==============================================================================

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VPC configuration"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda"
  type        = list(string)
}

# ==============================================================================
# Secrets Configuration
# ==============================================================================

variable "postgres_secret_arn" {
  description = "ARN of the Secrets Manager secret containing PostgreSQL credentials"
  type        = string
}

variable "twilio_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Twilio credentials"
  type        = string
}

# ==============================================================================
# Application Configuration
# ==============================================================================

variable "base_url" {
  description = "Base URL for renewal links (e.g., https://valo.ai)"
  type        = string
  default     = "https://valo.ai"
}

variable "batch_size" {
  description = "Number of users to process per invocation"
  type        = number
  default     = 100
}

# ==============================================================================
# Schedule Configuration
# ==============================================================================

variable "schedule_expression" {
  description = "EventBridge schedule expression (default: every hour)"
  type        = string
  default     = "rate(1 hour)"
}

# ==============================================================================
# Additional Configuration
# ==============================================================================

variable "environment_variables" {
  description = "Additional environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
