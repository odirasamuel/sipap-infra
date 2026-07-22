# Variables for core_deploy module
# SIPAP Lambda MCP deployment
#
# NOTE: Infrastructure values (VPC, subnets, database endpoints) are automatically
# fetched from the parent module's remote state. Only deployment-specific variables
# are defined here.

# ==============================================================================
# Core Configuration
# ==============================================================================

variable "stack_name" {
  description = "Stack name (e.g., sipap)"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# ==============================================================================
# MCP Token ARNs (from Secrets Manager)
# ==============================================================================
# These are created separately via create_mcp_tokens.sh script and are not
# part of the base infrastructure, so they remain as variables.

variable "data_mcp_token_arn" {
  description = "ARN of Data MCP authentication token in Secrets Manager"
  type        = string
}

variable "intelligence_mcp_token_arn" {
  description = "ARN of Intelligence MCP authentication token in Secrets Manager"
  type        = string
}

# ==============================================================================
# Lambda Configuration Overrides (Optional)
# ==============================================================================

variable "lambda_timeout_override" {
  description = "Override timeout values for Lambda functions (service -> seconds)"
  type        = map(number)
  default     = {}
}

variable "lambda_memory_override" {
  description = "Override memory values for Lambda functions (service -> MB)"
  type        = map(number)
  default     = {}
}

# ==============================================================================
# Feature Flags
# ==============================================================================

variable "enable_lambda_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_timeout_metric_filter" {
  description = "Enable CloudWatch metric filter for Lambda timeouts"
  type        = bool
  default     = true
}

# ==============================================================================
# Tags
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
