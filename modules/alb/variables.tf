variable "env" {
  description = "Name of the environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region to use"
  type        = string

  validation {
    condition     = var.aws_region == "us-gov-east-1" || var.aws_region == "us-gov-west-1"
    error_message = "aws_region must be one of: us-gov-east-1 or us-gov-west-1."
  }
}

variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "security_groups" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "stack_tool" {
  description = "Sentinel Component Tool Name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "alb_services" {
  type = list(object({
    name                = string
    stack_name          = string
    env                 = string
    aws_region          = string
    stack_tool          = string
    protocol            = string
    target_type         = string
    port                = number
    health_check_path   = optional(string, "/")
    health_check_port   = optional(string, null)
    timeout             = optional(number, 120)
    interval            = optional(number, 300)
    healthy_threshold   = optional(number, 5)
    unhealthy_threshold = optional(number, 5)
    enable_health_check = optional(bool, false)
  }))
}

variable "alb_internal" {
  description = "Whether the ALB is internal or internet-facing"
  type        = bool
  default     = false
}

variable "alb_certificate_arn" {
  description = "ARN of the SSL certificate for the ALB"
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Domain name for the ALB"
  type        = string
}

variable "ssl_policy" {
  description = "SSL policy for the ALB"
  type        = string
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for the ALB"
  type        = bool
  default     = true
}

variable "enable_tls_version_and_cipher_suite_headers" {
  description = "Whether to enable TLS version and cipher suite headers for the ALB"
  type        = bool
  default     = true
}

variable "enable_waf_fail_open" {
  description = "Whether to enable WAF fail open for the ALB"
  type        = bool
  default     = true
}