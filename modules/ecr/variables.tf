variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "repositories" {
  description = "List of ECR repositories to create"
  type = list(object({
    name                        = string
    image_tag_mutability        = optional(string, "MUTABLE")
    scan_on_push                = optional(bool, true)
    enable_cross_account_access = optional(bool, false)
    lifecycle_policy = optional(object({
      keep_last_images     = optional(number, 10)
      untagged_expire_days = optional(number, 7)
      }), {
      keep_last_images     = 10
      untagged_expire_days = 7
    })
  }))
  default = []

  validation {
    condition = alltrue([
      for repo in var.repositories : contains(["MUTABLE", "IMMUTABLE"], repo.image_tag_mutability)
    ])
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to ECR resources"
  type        = map(string)
  default     = {}
}