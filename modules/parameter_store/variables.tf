variable "parameter_name" {
  description = "Name of the SSM parameter"
  type        = string
}

variable "parameter_value" {
  description = "Value of the SSM parameter (JSON formatted)"
  type        = string
}

variable "parameter_description" {
  description = "Description of the SSM parameter"
  type        = string
  default     = "MCP API Gateway endpoint configuration"
}

variable "parameter_type" {
  description = "Type of SSM parameter"
  type        = string
  default     = "String"
}

variable "parameter_tier" {
  description = "SSM Parameter tier"
  type        = string
  default     = "Standard"
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
