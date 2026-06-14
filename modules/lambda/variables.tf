variable "internal_function_name" {
  description = "Name for the internal MCP server Lambda function"
  type        = string
}

variable "external_function_name" {
  description = "Name for the external MCP server Lambda function"
  type        = string
}

variable "function_source_dir" {
  description = "Source directory containing Lambda function code (required for local deployment)"
  type        = string
  default     = null
}

# S3-based deployment variables
variable "use_s3_deployment" {
  description = "Use S3-based deployment instead of local directory"
  type        = bool
  default     = false
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

variable "mcp_handler_layer_arn" {
  description = "ARN of the MCP handler layer (created by lambda_layers module)"
  type        = string
}

variable "dependencies_layer_arn" {
  description = "ARN of the dependencies layer (created by lambda_layers module)"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  type        = string
}

variable "mcp_token_arn" {
  description = "ARN of the MCP token secret in AWS Secrets Manager"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VPC configuration"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda functions"
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Function creation control
variable "create_internal_function" {
  description = "Whether to create the internal MCP server Lambda function"
  type        = bool
  default     = true
}

variable "create_external_function" {
  description = "Whether to create the external MCP server Lambda function"
  type        = bool
  default     = true
}

# Lambda configuration variables
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "lambda_architectures" {
  description = "Instruction set architecture for Lambda functions"
  type        = list(string)
  default     = ["x86_64"]
}

variable "lambda_handler" {
  description = "Function entrypoint in your code"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "lambda_timeout" {
  description = "Amount of time your Lambda function has to run in seconds"
  type        = number
  default     = 180
}

variable "lambda_memory_size" {
  description = "Amount of memory in MB your Lambda function can use at runtime"
  type        = number
  default     = 128
}

variable "lambda_ephemeral_storage_size" {
  description = "Amount of ephemeral storage in MB your Lambda function can use at runtime (512-10240 MB)"
  type        = number
  default     = 512
  validation {
    condition     = var.lambda_ephemeral_storage_size >= 512 && var.lambda_ephemeral_storage_size <= 10240
    error_message = "Ephemeral storage size must be between 512 and 10240 MB."
  }
}

variable "internal_lambda_environment_variables" {
  description = "Environment variables for internal Lambda function"
  type        = map(string)
  default     = {}
}

variable "external_lambda_environment_variables" {
  description = "Environment variables for external Lambda function"
  type        = map(string)
  default     = {}
}

variable "internal_lambda_description" {
  description = "Description for the internal Lambda function"
  type        = string
  default     = ""
}

variable "external_lambda_description" {
  description = "Description for the external Lambda function"
  type        = string
  default     = ""
}

variable "additional_internal_layer_arns" {
  description = "List of additional existing layer ARNs to attach to the internal Lambda function"
  type        = list(string)
  default     = []
}

variable "additional_external_layer_arns" {
  description = "List of additional existing layer ARNs to attach to the external Lambda function"
  type        = list(string)
  default     = []
}

# Lambda Function URL configuration
variable "enable_function_url" {
  description = "Whether to enable Lambda Function URLs for the functions"
  type        = bool
  default     = true
}

variable "function_url_auth_type" {
  description = "Authorization type for Function URL (NONE or AWS_IAM)"
  type        = string
  default     = "AWS_IAM"
  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth_type)
    error_message = "Authorization type must be either NONE or AWS_IAM."
  }
}

variable "function_url_cors" {
  description = "CORS configuration for Lambda Function URL"
  type = object({
    allow_credentials = optional(bool, false)
    allow_origins     = optional(list(string), ["*"])
    allow_methods     = optional(list(string), ["*"])
    allow_headers     = optional(list(string), ["*"])
    expose_headers    = optional(list(string), [])
    max_age           = optional(number, 0)
  })
  default = {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 0
  }
}

# Orchestrator task role ARN for Lambda invoke permissions
variable "orchestrator_task_role_arn" {
  description = "ARN of the orchestrator ECS task role (required for Lambda invoke permissions)"
  type        = string
  default     = null
}

variable "enable_orchestrator_invoke_permissions" {
  description = "Whether to create Lambda permissions for orchestrator task role invocation"
  type        = bool
  default     = false
}

# SSM Parameter Store Configuration
variable "create_ssm_parameter" {
  description = "Whether to create SSM parameter for internal Lambda Function URL"
  type        = bool
  default     = false
}

variable "create_ssm_parameter_external" {
  description = "Whether to create SSM parameter for external Lambda Function URL"
  type        = bool
  default     = false
}

variable "ssm_service_identifier" {
  description = "Service identifier for SSM parameter name (e.g., 'vantagepoint', 'winrm', 'sqlserver') for internal function"
  type        = string
  default     = ""
}

variable "ssm_service_identifier_external" {
  description = "Service identifier for SSM parameter name for external function"
  type        = string
  default     = ""
}

variable "ssm_parameter_name_override" {
  description = "Override for SSM parameter name for internal function (default: /sre/sentinel-mcp-{service_identifier})"
  type        = string
  default     = ""
}

variable "ssm_parameter_name_override_external" {
  description = "Override for SSM parameter name for external function"
  type        = string
  default     = ""
}

variable "ssm_mcp_timeout" {
  description = "Timeout value (in seconds) for MCP endpoint"
  type        = number
  default     = 300
}