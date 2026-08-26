# Payment Webhook Lambda Module Variables
# Supports both local and S3-based deployment

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "function_description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "Payment webhook handler for SIPAP (Stripe, Paystack, and Flutterwave)"
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# ==============================================================================
# Deployment Configuration (Local vs S3)
# ==============================================================================

variable "use_s3_deployment" {
  description = "Use S3-based deployment instead of local directory"
  type        = bool
  default     = false
}

variable "function_source_dir" {
  description = "Path to the Lambda function source directory (required for local deployment)"
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key (path) to the Lambda deployment package"
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "Specific S3 object version to deploy (optional, leave null to use latest)"
  type        = string
  default     = null
}

variable "s3_source_code_hash" {
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
  default     = "python3.12"
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
  default     = 30
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

variable "stripe_webhook_secret" {
  description = "Stripe webhook signing secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "paystack_secret_key" {
  description = "Paystack secret key for webhook verification"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flutterwave_webhook_secret" {
  description = "Flutterwave webhook secret for verification (verif-hash header)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "twilio_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Twilio credentials"
  type        = string
  default     = ""
}

# ==============================================================================
# Notification Queue Configuration (for failed WhatsApp notifications)
# ==============================================================================

variable "notification_queue_url" {
  description = "URL of the SQS queue for failed WhatsApp notification retries"
  type        = string
  default     = ""
}

variable "notification_queue_arn" {
  description = "ARN of the SQS queue for failed WhatsApp notification retries"
  type        = string
  default     = ""
}

# ==============================================================================
# API Gateway Permission
# ==============================================================================

variable "enable_api_gateway_permission" {
  description = "Whether to create API Gateway invoke permission"
  type        = bool
  default     = true
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  type        = string
  default     = ""
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
