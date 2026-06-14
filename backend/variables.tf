variable "stack_name" {
  description = "Name of the stack"
  type        = string
  default     = "sipap"
}

variable "profile" {
  description = "AWS profile to use"
  type        = string
  default     = "odiraaws"
}

variable "region" {
  description = "AWS region to use"
  type        = string
  default     = "us-west-1"
}

variable "env" {
  description = "Name of the environment"
  type        = string
  default     = "dev"
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default = {
    "Project"     = "SIPAP"
    "Environment" = "dev"
    "ManagedBy"   = "Terraform"
    "DeployedVia" = "Manual"
  }
}