variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Name of the environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region to use"
  type        = string
}

variable "stack_tool" {
  description = "SIG tools"
  type        = string
}

variable "role_description" {
  description = "Description of the role"
  type        = string
}

variable "assume_role_policy" {
  description = "IAM policy document specifying who can assume the role"
  type        = any
}

variable "inline_policies" {
  description = "List of inline IAM policies. Each object must have 'name' and 'policy'."
  type = list(object({
    name   = string
    policy = string
  }))
}

variable "managed_policy_arns" {
  description = "List of AWS managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}