# Gateway Configuration
variable "gateway_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "gateway_type" {
  description = "Type of API Gateway (rest_api or http_api)"
  type        = string
  validation {
    condition     = contains(["rest_api", "http_api"], var.gateway_type)
    error_message = "Gateway type must be either 'rest_api' or 'http_api'."
  }
}

variable "integration_type" {
  description = "Integration type (sqs or lambda)"
  type        = string
  validation {
    condition     = contains(["sqs", "lambda"], var.integration_type)
    error_message = "Integration type must be either 'sqs' or 'lambda'."
  }
}

variable "description" {
  description = "Description of the API Gateway"
  type        = string
  default     = ""
}

variable "endpoint_type" {
  description = "Endpoint type (REGIONAL, EDGE, or PRIVATE)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "EDGE", "PRIVATE"], var.endpoint_type)
    error_message = "Endpoint type must be REGIONAL, EDGE, or PRIVATE."
  }
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for the domain name"
  type        = string
  default     = "TLS_1_2"
}

# SQS Integration Variables
variable "sqs_queue_arn" {
  description = "ARN of the SQS queue for integration (required when integration_type = sqs)"
  type        = string
  default     = ""
}

variable "sqs_region" {
  description = "AWS region where SQS queue is located"
  type        = string
  default     = ""
}

variable "sqs_execution_role_arn" {
  description = "ARN of IAM role for SQS integration"
  type        = string
  default     = ""
}

variable "sqs_message_group_id" {
  description = "Message group ID for FIFO SQS queue"
  type        = string
  default     = "sentinel"
}

# Lambda Integration Variables
variable "lambda_function_arn" {
  description = "ARN of the Lambda function for integration (required when integration_type = lambda)"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for permissions"
  type        = string
  default     = ""
}

variable "routes" {
  description = "List of routes for HTTP API (when gateway_type = http_api)"
  type = list(object({
    method = string
    path   = string
  }))
  default = [
    {
      method = "GET"
      path   = "/health"
    },
    {
      method = "POST"
      path   = "/mcp"
    }
  ]
}

variable "lambda_rest_api_resource_path" {
  description = "Resource path for REST API Lambda integration"
  type        = string
  default     = "lambda"
}

variable "lambda_rest_api_methods" {
  description = "HTTP methods for REST API Lambda integration"
  type        = list(string)
  default     = ["ANY"]
}

# Usage Plan Variables (for REST API)
variable "create_usage_plan" {
  description = "Whether to create a usage plan (only for REST API)"
  type        = bool
  default     = true
}

variable "usage_plan_name" {
  description = "Name of the usage plan"
  type        = string
  default     = ""
}

variable "usage_plan_description" {
  description = "Description of the usage plan"
  type        = string
  default     = ""
}

variable "throttle_rate_limit" {
  description = "Throttle rate limit for usage plan"
  type        = number
  default     = 50
}

variable "throttle_burst_limit" {
  description = "Throttle burst limit for usage plan"
  type        = number
  default     = 20
}

variable "quota_limit" {
  description = "Request quota limit for usage plan"
  type        = number
  default     = 1000
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

# API Key Variables
variable "create_api_key" {
  description = "Whether to create an API key"
  type        = bool
  default     = true
}

variable "api_key_name" {
  description = "Name of the API key"
  type        = string
  default     = ""
}

# Stage Configuration
variable "stage_name" {
  description = "Name of the deployment stage"
  type        = string
  default     = "prod"
}

variable "stage_auto_deploy" {
  description = "Whether to enable auto-deploy for HTTP API stage"
  type        = bool
  default     = true
}

# Common Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Observability Configuration Variables
variable "enable_execution_logs" {
  description = "Enable execution logging for API Gateway (CloudWatch Logs)"
  type        = bool
  default     = true
}

variable "logging_level" {
  description = "Logging level for execution logs (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be OFF, ERROR, or INFO."
  }
}

variable "enable_detailed_metrics" {
  description = "Enable detailed CloudWatch metrics"
  type        = bool
  default     = true
}

variable "enable_data_trace" {
  description = "Enable full request/response data logging (use carefully - can log sensitive data)"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for API Gateway"
  type        = bool
  default     = true
}

variable "xray_tracing_enabled" {
  description = "X-Ray tracing mode (true for Active, false for PassThrough)"
  type        = bool
  default     = true
}

variable "enable_access_logging" {
  description = "Enable access logging to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "access_log_format" {
  description = "Access log format (JSON or CLF). If empty, uses AWS default JSON format."
  type        = string
  default     = ""
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

variable "cloudwatch_role_arn" {
  description = "ARN of IAM role for API Gateway to write to CloudWatch Logs (required for execution logs)"
  type        = string
  default     = ""
}

# SSM Parameter Store Configuration
variable "create_ssm_parameter" {
  description = "Whether to create an SSM parameter for HTTP API Gateway endpoint"
  type        = bool
  default     = true
}

variable "ssm_service_identifier" {
  description = "Service identifier for SSM parameter name (e.g., 'vantagepoint', 'winrm', 'sqlserver')"
  type        = string
  default     = ""
}

variable "ssm_parameter_name_override" {
  description = "Override for SSM parameter name (default: /sre/sentinel-mcp-{service_identifier})"
  type        = string
  default     = ""
}

variable "ssm_mcp_timeout" {
  description = "Timeout value (in seconds) for MCP endpoint"
  type        = number
  default     = 300
}

# Custom Domain Configuration
variable "enable_custom_domain" {
  description = "Whether to create a custom domain for this API Gateway"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the API Gateway (e.g., mcp.engdeltek.com)"
  type        = string
  default     = ""
}

variable "custom_domain_certificate_arn" {
  description = "ACM certificate ARN for the custom domain (must be in us-east-1 for edge-optimized)"
  type        = string
  default     = ""
}

variable "custom_domain_base_path" {
  description = "Base path for API mapping (e.g., 'v1', 'api'). Leave empty for root path."
  type        = string
  default     = ""
}

variable "custom_domain_security_policy" {
  description = "Security policy for the custom domain (TLS_1_2 or TLS_1_3)"
  type        = string
  default     = "TLS_1_2"
  validation {
    condition     = contains(["TLS_1_2", "TLS_1_3"], var.custom_domain_security_policy)
    error_message = "Security policy must be TLS_1_2 or TLS_1_3."
  }
}