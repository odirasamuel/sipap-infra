variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "services" {
  description = "List of ECS services to create"
  type = list(object({
    name          = string
    image         = string
    cpu           = number
    memory        = number
    desired_count = number
    task_role_arn = optional(string, null)

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

    security_group_ids = list(string)

    load_balancer_config = optional(object({
      target_group_arn = string
      container_port   = number
    }), null)

    deployment_configuration = optional(object({
      maximum_percent         = optional(number, 200)
      minimum_healthy_percent = optional(number, 100)
      }), {
      maximum_percent         = 200
      minimum_healthy_percent = 100
    })

    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    }), null)

    # EFS volumes configuration
    efs_volumes = optional(list(object({
      name            = string
      file_system_id  = string
      root_directory  = optional(string, "/")
      access_point_id = optional(string, null)
    })), [])

    # Mount points for EFS volumes
    mount_points = optional(list(object({
      source_volume  = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])

    # Container initialization
    command    = optional(list(string), null)
    entrypoint = optional(list(string), null)

    # Container definition overrides for advanced configuration
    container_definition_overrides = optional(object({
      essential = optional(bool, true)
      user      = optional(string, null)
      healthCheck = optional(object({
        command     = list(string)
        interval    = optional(number, 30)
        timeout     = optional(number, 5)
        retries     = optional(number, 3)
        startPeriod = optional(number, 60)
      }), null)
      logConfiguration = optional(object({
        logDriver = string
        options   = map(string)
      }), null)
    }), null)

    enable_deployment_circuit_breaker = optional(bool, true)
    enable_deployment_rollback        = optional(bool, true)
  }))
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the ECS cluster"
  type        = bool
  default     = true
}

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = false
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "additional_tags" {
  description = "Additional tags to apply to ECS resources"
  type        = map(string)
  default     = {}
}