variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "odirasamuel"
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
  default     = "sipap"
}

variable "env" {
  description = "Environment name (used for S3 bucket naming and resource tagging)"
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

variable "lifecycle_noncurrent_days" {
  description = "Number of days to retain noncurrent S3 object versions"
  type        = number
  default     = 90
}
