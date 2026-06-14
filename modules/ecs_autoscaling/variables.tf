variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "service_role_arn" {
  description = "ARN of the service role for Application Auto Scaling"
  type        = string
}

variable "ecs_services" {
  description = "List of ECS services to configure for auto scaling"
  type = list(object({
    name         = string
    service_name = string
    min_capacity = number
    max_capacity = number

    # CPU-based scaling
    enable_cpu_scaling = optional(bool, true)
    cpu_target_value   = optional(number, 70)

    # Memory-based scaling
    enable_memory_scaling = optional(bool, false)
    memory_target_value   = optional(number, 80)

    # Cooldown periods (seconds)
    scale_in_cooldown  = optional(number, 300)
    scale_out_cooldown = optional(number, 300)

    # Step scaling configuration
    enable_step_scaling = optional(bool, false)
    cpu_high_threshold  = optional(number, 80)
    cpu_low_threshold   = optional(number, 20)

    step_scaling_config = optional(object({
      scale_up_adjustments = list(object({
        metric_interval_lower_bound = number
        metric_interval_upper_bound = optional(number, null)
        scaling_adjustment          = number
      }))
      scale_down_adjustments = list(object({
        metric_interval_lower_bound = optional(number, null)
        metric_interval_upper_bound = number
        scaling_adjustment          = number
      }))
    }), null)

    # Custom metric scaling (e.g., ALB request count)
    custom_metric_scaling = optional(object({
      target_value     = number
      disable_scale_in = optional(bool, false)

      predefined_metric = optional(object({
        metric_type    = string
        resource_label = optional(string, null)
      }), null)

      custom_metric = optional(object({
        metric_name = string
        namespace   = string
        statistic   = string
        unit        = optional(string, null)
        dimensions = list(object({
          name  = string
          value = string
        }))
      }), null)
    }), null)

    # Scheduled scaling
    scheduled_scaling = optional(list(object({
      name         = string
      schedule     = string
      min_capacity = number
      max_capacity = number
    })), [])
  }))

  validation {
    condition = alltrue([
      for service in var.ecs_services : service.max_capacity >= service.min_capacity
    ])
    error_message = "max_capacity must be greater than or equal to min_capacity for all services."
  }

  validation {
    condition = alltrue([
      for service in var.ecs_services : service.min_capacity >= 1
    ])
    error_message = "min_capacity must be at least 1 for all services."
  }

  validation {
    condition = alltrue([
      for service in var.ecs_services : service.cpu_target_value >= 10 && service.cpu_target_value <= 90
    ])
    error_message = "cpu_target_value must be between 10 and 90 for all services."
  }

  validation {
    condition = alltrue([
      for service in var.ecs_services : service.memory_target_value >= 10 && service.memory_target_value <= 90
    ])
    error_message = "memory_target_value must be between 10 and 90 for all services."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for auto scaling"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "alarm_evaluation_periods must be between 1 and 5."
  }
}

variable "alarm_period" {
  description = "Period for CloudWatch alarms in seconds"
  type        = number
  default     = 300
}

variable "additional_tags" {
  description = "Additional tags to apply to auto scaling resources"
  type        = map(string)
  default     = {}
}