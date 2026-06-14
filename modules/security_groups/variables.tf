variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Name of the environment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
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

variable "ingress_rules" {
  description = "List of ingress rule objects."
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = list(string)
    ipv6_cidr_blocks = list(string)
    security_groups  = list(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rule objects."
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = list(string)
    ipv6_cidr_blocks = list(string)
  }))
  default = []
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}