# WhatsApp API Gateway Module Variables

variable "stack_name" {
  description = "Stack name (e.g., sipap)"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "sqs_queue_url" {
  description = "URL of the SQS queue for message delivery"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue for IAM policy"
  type        = string
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for API Gateway"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 90
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "throttle_rate_limit" {
  description = "Throttle rate limit for usage plan (requests per second)"
  type        = number
  default     = 50
}

variable "throttle_burst_limit" {
  description = "Throttle burst limit for usage plan (concurrent requests)"
  type        = number
  default     = 20
}

variable "quota_limit" {
  description = "Request quota limit for usage plan"
  type        = number
  default     = 10000
}

variable "quota_period" {
  description = "Time period for quota (DAY, WEEK, or MONTH)"
  type        = string
  default     = "DAY"
  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.quota_period)
    error_message = "Quota period must be DAY, WEEK, or MONTH."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Lambda Integration Variables (for auth handler)
variable "use_lambda_integration" {
  description = "Use Lambda proxy integration instead of direct SQS integration"
  type        = bool
  default     = false
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function for proxy integration"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for resource-based policy"
  type        = string
  default     = ""
}

variable "additional_deployment_triggers" {
  description = "Additional trigger values for deployment redeployment (e.g., from external API Gateway routes). When these values change, the deployment will be recreated."
  type        = map(string)
  default     = {}
}
