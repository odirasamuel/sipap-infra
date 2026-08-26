# Payment Session Lambda Module Variables

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "function_description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "Payment session handler for creating Flutterwave checkout sessions"
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
  description = "Specific S3 object version to deploy (optional)"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64-encoded SHA256 hash of the package file (triggers redeployment on change)"
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
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "layer_arns" {
  description = "List of Lambda layer ARNs to attach"
  type        = list(string)
  default     = []
}

# ==============================================================================
# Secrets Configuration
# ==============================================================================

variable "flutterwave_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Flutterwave credentials"
  type        = string
}

variable "redirect_url" {
  description = "URL to redirect user after payment completion"
  type        = string
  default     = "https://ridhatech.com/payment-success"
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
