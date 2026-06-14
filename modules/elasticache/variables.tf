variable "cache_name" {
  description = "Name of the ElastiCache serverless cache"
  type        = string
  default     = "sentinel-valkey-sessions"
}

variable "engine" {
  description = "Cache engine to use"
  type        = string
  default     = "valkey"
  validation {
    condition     = contains(["redis", "valkey", "memcached"], var.engine)
    error_message = "Engine must be redis, valkey, or memcached."
  }
}

variable "major_engine_version" {
  description = "Major version of the cache engine"
  type        = string
  default     = "8"
}

variable "description" {
  description = "Description of the serverless cache"
  type        = string
  default     = "Sentinel Valkey cache for session storage"
}

variable "kms_key_id" {
  description = "KMS key ID for encryption at rest"
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cache"
  type        = list(string)
}

variable "user_group_id" {
  description = "User group ID for access control"
  type        = string
  default     = null
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 1
}

variable "daily_snapshot_time" {
  description = "Time of day for daily snapshots (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "use_serverless" {
  description = "Use ElastiCache Serverless (true) or standard instance (false)"
  type        = bool
  default     = false
}

variable "node_type" {
  description = "Node type for standard ElastiCache (used when use_serverless = false)"
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_nodes" {
  description = "Number of cache nodes for standard ElastiCache"
  type        = number
  default     = 1
}

variable "parameter_group_name" {
  description = "Parameter group name for standard ElastiCache"
  type        = string
  default     = "default.redis7"
}

variable "additional_tags" {
  description = "Additional tags to apply to the cache"
  type        = map(string)
  default     = {}
}

# Cache Data Storage (for Serverless mode)
variable "cache_usage_limits" {
  description = "Cache usage limits configuration"
  type = object({
    data_storage = object({
      maximum = number
      unit    = string
    })
    ecpu_per_second = object({
      maximum = number
    })
  })
  default = {
    data_storage = {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second = {
      maximum = 1000
    }
  }
}