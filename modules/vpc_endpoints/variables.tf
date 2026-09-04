variable "vpc_id" {
  description = "VPC ID where endpoints will be created"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used to construct service endpoint names)"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource tagging"
  type        = string
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "private_route_table_ids" {
  description = "Private route table IDs to associate with gateway endpoints"
  type        = list(string)
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
