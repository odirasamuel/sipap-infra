variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for DB subnet group"
  type        = list(string)
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
}

variable "master_username" {
  description = "Master username for Aurora"
  type        = string
}

variable "min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 1.0
}

variable "allowed_cidrs" {
  description = "List of CIDR blocks allowed to access Aurora"
  type        = list(string)
}

variable "use_serverless" {
  description = "Use Aurora Serverless v2 (true) or standard RDS instance (false)"
  type        = bool
  default     = false
}

variable "instance_class" {
  description = "Instance class for standard RDS (used when use_serverless = false)"
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version_standard" {
  description = "PostgreSQL engine version for standard RDS instances"
  type        = string
  default     = "15.17"
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
