# Core variables
variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
  default     = "sipap"
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# VPC configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "172.31.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["172.31.11.0/24", "172.31.12.0/24", "172.31.13.0/24"]
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways to create (1 for cost optimization, 3 for high availability)"
  type        = number
  default     = 1
}

# Database configuration (mode selection)
variable "aurora_use_serverless" {
  description = "Use Aurora Serverless v2 (true) or standard RDS instance (false) for cost optimization"
  type        = bool
  default     = false
}

variable "aurora_instance_class" {
  description = "Instance class for standard RDS (used when aurora_use_serverless = false)"
  type        = string
  default     = "db.t4g.micro"
}

# Cache configuration (mode selection)
variable "elasticache_use_serverless" {
  description = "Use ElastiCache Serverless (true) or standard instance (false) for cost optimization"
  type        = bool
  default     = false
}

variable "elasticache_node_type" {
  description = "Node type for standard ElastiCache (used when elasticache_use_serverless = false)"
  type        = string
  default     = "cache.t4g.micro"
}

# Database configuration (existing)
variable "database_name" {
  description = "Aurora database name"
  type        = string
  default     = "sipap"
}

variable "db_master_username" {
  description = "Aurora master username"
  type        = string
  default     = "sipap_admin"
}

variable "additional_tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
