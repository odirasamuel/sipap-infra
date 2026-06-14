output "autoscaling_target_arns" {
  description = "Map of service names to their auto scaling target ARNs"
  value = {
    for service_name, target in aws_appautoscaling_target.ecs_service : service_name => target.arn
  }
}

output "autoscaling_target_resource_ids" {
  description = "Map of service names to their auto scaling target resource IDs"
  value = {
    for service_name, target in aws_appautoscaling_target.ecs_service : service_name => target.resource_id
  }
}

output "cpu_scaling_policy_arns" {
  description = "Map of service names to their CPU-based scaling policy ARNs"
  value = {
    for service_name, policy in aws_appautoscaling_policy.scale_up_cpu : service_name => policy.arn
  }
}

output "memory_scaling_policy_arns" {
  description = "Map of service names to their memory-based scaling policy ARNs"
  value = {
    for service_name, policy in aws_appautoscaling_policy.scale_up_memory : service_name => policy.arn
  }
}

output "custom_metric_scaling_policy_arns" {
  description = "Map of service names to their custom metric scaling policy ARNs"
  value = {
    for service_name, policy in aws_appautoscaling_policy.scale_custom_metric : service_name => policy.arn
  }
}

output "step_scaling_up_policy_arns" {
  description = "Map of service names to their step scaling up policy ARNs"
  value = {
    for service_name, policy in aws_appautoscaling_policy.step_scaling_up : service_name => policy.arn
  }
}

output "step_scaling_down_policy_arns" {
  description = "Map of service names to their step scaling down policy ARNs"
  value = {
    for service_name, policy in aws_appautoscaling_policy.step_scaling_down : service_name => policy.arn
  }
}

output "high_cpu_alarm_arns" {
  description = "Map of service names to their high CPU alarm ARNs"
  value = {
    for service_name, alarm in aws_cloudwatch_metric_alarm.high_cpu : service_name => alarm.arn
  }
}

output "low_cpu_alarm_arns" {
  description = "Map of service names to their low CPU alarm ARNs"
  value = {
    for service_name, alarm in aws_cloudwatch_metric_alarm.low_cpu : service_name => alarm.arn
  }
}

output "scheduled_action_arns" {
  description = "Map of scheduled action names to their ARNs"
  value = {
    for action_name, action in aws_appautoscaling_scheduled_action.scheduled_scaling : action_name => action.arn
  }
}

output "scaling_summary" {
  description = "Summary of auto scaling configuration for all services"
  value = {
    for service_name, target in aws_appautoscaling_target.ecs_service : service_name => {
      resource_id    = target.resource_id
      min_capacity   = target.min_capacity
      max_capacity   = target.max_capacity
      cpu_scaling    = contains(keys(aws_appautoscaling_policy.scale_up_cpu), service_name)
      memory_scaling = contains(keys(aws_appautoscaling_policy.scale_up_memory), service_name)
      custom_scaling = contains(keys(aws_appautoscaling_policy.scale_custom_metric), service_name)
      step_scaling   = contains(keys(aws_appautoscaling_policy.step_scaling_up), service_name)
    }
  }
}