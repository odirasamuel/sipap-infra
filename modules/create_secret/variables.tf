variable "secret_string" {
  description = "The secret string to store"
  type        = any
  sensitive   = true
}

variable "secret_name" {
  description = "The name of the secret"
  type        = string
}

variable "secret_description" {
  description = "The description of the secret"
  type        = string
}

variable "replica_region" {
  description = "The region to replicate the secret to (optional, must be different from primary region)"
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
