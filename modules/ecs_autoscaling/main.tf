# Description: This module creates Application Auto Scaling resources for ECS services with CPU/memory-based scaling policies

# Application Auto Scaling Target for each ECS service
resource "aws_appautoscaling_target" "ecs_service" {
  for_each = { for service in var.ecs_services : service.name => service }

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${var.cluster_name}/${each.value.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  role_arn           = var.service_role_arn

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-scaling-target"
  }, var.additional_tags)
}

# CPU-based Scale Up Policy
resource "aws_appautoscaling_policy" "scale_up_cpu" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_cpu_scaling }

  name               = "${each.value.name}-scale-up-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = each.value.cpu_target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}

# Memory-based Scale Up Policy
resource "aws_appautoscaling_policy" "scale_up_memory" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_memory_scaling }

  name               = "${each.value.name}-scale-up-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = each.value.memory_target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}

# Custom Metric Scaling (e.g., ALB Request Count)
resource "aws_appautoscaling_policy" "scale_custom_metric" {
  for_each = { for service in var.ecs_services : service.name => service if service.custom_metric_scaling != null }

  name               = "${each.value.name}-scale-custom"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    dynamic "predefined_metric_specification" {
      for_each = each.value.custom_metric_scaling.predefined_metric != null ? [each.value.custom_metric_scaling.predefined_metric] : []
      content {
        predefined_metric_type = predefined_metric_specification.value.metric_type
        resource_label         = predefined_metric_specification.value.resource_label
      }
    }

    dynamic "customized_metric_specification" {
      for_each = each.value.custom_metric_scaling.custom_metric != null ? [each.value.custom_metric_scaling.custom_metric] : []
      content {
        metric_name = customized_metric_specification.value.metric_name
        namespace   = customized_metric_specification.value.namespace
        statistic   = customized_metric_specification.value.statistic
        unit        = customized_metric_specification.value.unit

        dynamic "dimensions" {
          for_each = customized_metric_specification.value.dimensions
          content {
            name  = dimensions.value.name
            value = dimensions.value.value
          }
        }
      }
    }

    target_value       = each.value.custom_metric_scaling.target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
    disable_scale_in   = each.value.custom_metric_scaling.disable_scale_in
  }
}

# Step Scaling Policies (Advanced scaling)
resource "aws_appautoscaling_policy" "step_scaling_up" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_step_scaling }

  name               = "${each.value.name}-step-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.scale_out_cooldown
    metric_aggregation_type = "Average"

    dynamic "step_adjustment" {
      for_each = each.value.step_scaling_config.scale_up_adjustments
      content {
        metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
        metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
        scaling_adjustment          = step_adjustment.value.scaling_adjustment
      }
    }
  }
}

resource "aws_appautoscaling_policy" "step_scaling_down" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_step_scaling }

  name               = "${each.value.name}-step-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.scale_in_cooldown
    metric_aggregation_type = "Average"

    dynamic "step_adjustment" {
      for_each = each.value.step_scaling_config.scale_down_adjustments
      content {
        metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
        metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
        scaling_adjustment          = step_adjustment.value.scaling_adjustment
      }
    }
  }
}

# CloudWatch Alarms for Step Scaling
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_step_scaling }

  alarm_name          = "${each.value.name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.cpu_high_threshold
  alarm_description   = "This metric monitors ECS CPU utilization for scaling up"

  dimensions = {
    ServiceName = each.value.service_name
    ClusterName = var.cluster_name
  }

  alarm_actions = [aws_appautoscaling_policy.step_scaling_up[each.key].arn]

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-high-cpu-alarm"
  }, var.additional_tags)
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  for_each = { for service in var.ecs_services : service.name => service if service.enable_step_scaling }

  alarm_name          = "${each.value.name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.cpu_low_threshold
  alarm_description   = "This metric monitors ECS CPU utilization for scaling down"

  dimensions = {
    ServiceName = each.value.service_name
    ClusterName = var.cluster_name
  }

  alarm_actions = [aws_appautoscaling_policy.step_scaling_down[each.key].arn]

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-low-cpu-alarm"
  }, var.additional_tags)
}

# Scheduled Scaling (optional)
resource "aws_appautoscaling_scheduled_action" "scheduled_scaling" {
  for_each = { for idx, schedule in local.scheduled_actions : "${schedule.service_name}-${idx}" => schedule }

  name               = "${each.value.service_name}-scheduled-${each.value.name}"
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${each.value.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  schedule           = each.value.schedule

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}

# Local values for processing scheduled actions
locals {
  scheduled_actions = flatten([
    for service in var.ecs_services : [
      for schedule in service.scheduled_scaling : {
        service_name = service.service_name
        name         = schedule.name
        schedule     = schedule.schedule
        min_capacity = schedule.min_capacity
        max_capacity = schedule.max_capacity
      }
    ]
  ])
}