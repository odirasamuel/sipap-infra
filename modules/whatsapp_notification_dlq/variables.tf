# Variables for WhatsApp Notification DLQ Module

variable "stack_name" {
  description = "Name of the stack (used for resource naming)"
  type        = string
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "payment_webhook_role_arn" {
  description = "ARN of the IAM role used by the Payment Webhook Lambda (needs SendMessage permission). If not provided, account-level access is granted."
  type        = string
  default     = ""
}

variable "twilio_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Twilio credentials"
  type        = string
}

variable "lambda_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "lambda_s3_key" {
  description = "S3 key for the Lambda deployment package"
  type        = string
  default     = "lambda-packages/notification-retry-handler.zip"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
