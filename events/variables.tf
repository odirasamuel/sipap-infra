variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
  default     = "sipap"
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Lambda S3 source configuration
variable "lambda_s3_bucket" {
  description = "S3 bucket containing Lambda deployment packages"
  type        = string
  default     = "sipap-lambda-packages-dev"
}

variable "lambda_s3_key_prefix" {
  description = "S3 key prefix for Lambda deployment packages"
  type        = string
  default     = "batch-scraper"
}
