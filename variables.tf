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

# ECS Services Configuration
variable "ecs_services" {
  description = "List of ECS services to deploy (e.g., orchestrator)"
  type = list(object({
    name          = string
    image         = string
    cpu           = number
    memory        = number
    desired_count = number

    port_mappings = list(object({
      container_port = number
      protocol       = optional(string, "tcp")
    }))

    environment_variables = optional(list(object({
      name  = string
      value = string
    })), [])

    secrets = optional(list(object({
      name       = string
      value_from = string
    })), [])

    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    }), null)

    deployment_configuration = optional(object({
      maximum_percent         = optional(number, 200)
      minimum_healthy_percent = optional(number, 100)
      }), {
      maximum_percent         = 200
      minimum_healthy_percent = 100
    })

    enable_deployment_circuit_breaker = optional(bool, true)
    enable_deployment_rollback        = optional(bool, true)
  }))
  default = [] # Empty by default, populated in tfvars
}

# ============================================================================
# AUTOSCALING CONFIGURATION
# ============================================================================

variable "orchestrator_autoscaling" {
  description = "Autoscaling configuration for orchestrator-service. Uses SQS queue depth as primary scaling metric."
  type = object({
    min_capacity           = number  # Minimum number of tasks (always running)
    max_capacity           = number  # Maximum number of tasks (cost control)
    sqs_scale_up_threshold = number  # Queue depth to trigger scale up
  })
  default = {
    min_capacity           = 1  # Always keep 1 task for instant first response
    max_capacity           = 4  # Cost-optimized MVP (~$140/mo max)
    sqs_scale_up_threshold = 3  # Scale up when 3+ messages waiting
  }

  validation {
    condition     = var.orchestrator_autoscaling.min_capacity >= 1
    error_message = "min_capacity must be at least 1."
  }

  validation {
    condition     = var.orchestrator_autoscaling.max_capacity >= var.orchestrator_autoscaling.min_capacity
    error_message = "max_capacity must be >= min_capacity."
  }

  validation {
    condition     = var.orchestrator_autoscaling.sqs_scale_up_threshold >= 1
    error_message = "sqs_scale_up_threshold must be at least 1."
  }
}
