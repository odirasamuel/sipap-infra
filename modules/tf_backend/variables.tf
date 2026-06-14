variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Name of the environment"
  type        = string
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region to use"
  type        = string
  default     = "us-west-1"
}