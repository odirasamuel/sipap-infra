# Variables for Lambda Layers Module

# ==============================================================================
# Deployment Method
# ==============================================================================

variable "use_s3_deployment" {
  description = "Use S3-based deployment instead of local directory"
  type        = bool
  default     = false
}

variable "s3_bucket" {
  description = "S3 bucket containing the Lambda layer packages"
  type        = string
  default     = null
}

# ==============================================================================
# MCP Handler Layer Configuration
# ==============================================================================

variable "create_mcp_handler_layer" {
  description = "Whether to create the MCP handler layer"
  type        = bool
  default     = true
}

variable "mcp_handler_s3_key" {
  description = "S3 key (path) to the MCP handler layer package"
  type        = string
  default     = null
}

variable "mcp_handler_s3_version" {
  description = "Specific S3 object version for MCP handler layer (optional, leave null to use latest)"
  type        = string
  default     = null
}

variable "mcp_handler_source_dir" {
  description = "Source directory for the MCP handler layer (required for local deployment)"
  type        = string
  default     = null
}

variable "mcp_handler_layer_name" {
  description = "Name for the MCP handler layer"
  type        = string
  default     = "sipap-serverless-mcp-handler"
}

variable "mcp_handler_description" {
  description = "Description for the MCP handler layer"
  type        = string
  default     = "SIPAP MCP Server Engine"
}

# ==============================================================================
# Dependencies Layer Configuration
# ==============================================================================

variable "create_dependencies_layer" {
  description = "Whether to create the dependencies layer"
  type        = bool
  default     = false
}

variable "dependencies_s3_key" {
  description = "S3 key (path) to the dependencies layer package"
  type        = string
  default     = null
}

variable "dependencies_s3_version" {
  description = "Specific S3 object version for dependencies layer (optional, leave null to use latest)"
  type        = string
  default     = null
}

variable "dependencies_source_dir" {
  description = "Source directory for the dependencies layer (required for local deployment)"
  type        = string
  default     = null
}

variable "dependencies_layer_name" {
  description = "Name for the dependencies layer"
  type        = string
  default     = "sipap-dependencies"
}

variable "dependencies_description" {
  description = "Description for the dependencies layer"
  type        = string
  default     = "Dependencies for SIPAP"
}

# ==============================================================================
# Runtime Compatibility
# ==============================================================================

variable "compatible_runtimes" {
  description = "List of compatible runtimes for the layers"
  type        = list(string)
  default     = ["python3.12", "python3.13", "python3.14"]
}

variable "compatible_architectures" {
  description = "List of compatible architectures for the layers"
  type        = list(string)
  default     = ["x86_64"]
}

# ==============================================================================
# Tags
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
