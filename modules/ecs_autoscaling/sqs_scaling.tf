# SQS Queue Depth-Based Autoscaling for ECS Services
#
# This file provides CloudWatch alarms and step scaling policies for
# queue-based workloads like the SIPAP orchestrator. It scales based on
# ApproximateNumberOfMessagesVisible in SQS, which directly reflects
# user demand for I/O-bound services that wait on external APIs.

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# Scale Up Alarm - Triggered when queue depth is high
resource "aws_cloudwatch_metric_alarm" "sqs_scale_up" {
  for_each = { for svc in var.ecs_services : svc.name => svc if svc.sqs_scaling_config != null }

  alarm_name          = "${var.stack_name}-${var.env}-${each.value.name}-sqs-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = each.value.sqs_scaling_config.scale_up_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = each.value.sqs_scaling_config.scale_up_period
  statistic           = "Average"
  threshold           = each.value.sqs_scaling_config.scale_up_threshold
  alarm_description   = "Scale up ECS service when SQS queue depth >= ${each.value.sqs_scaling_config.scale_up_threshold} messages"

  dimensions = {
    QueueName = each.value.sqs_scaling_config.queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.sqs_scale_up[each.key].arn]

  tags = merge({
    Name    = "${var.stack_name}-${var.env}-${each.value.name}-sqs-high-alarm"
    Purpose = "ECS autoscaling based on SQS queue depth"
  }, var.additional_tags)
}

# Scale Down Alarm - Triggered when queue is empty for sustained period
resource "aws_cloudwatch_metric_alarm" "sqs_scale_down" {
  for_each = { for svc in var.ecs_services : svc.name => svc if svc.sqs_scaling_config != null }

  alarm_name          = "${var.stack_name}-${var.env}-${each.value.name}-sqs-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = each.value.sqs_scaling_config.scale_down_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = each.value.sqs_scaling_config.scale_down_period
  statistic           = "Average"
  threshold           = each.value.sqs_scaling_config.scale_down_threshold
  alarm_description   = "Scale down ECS service when SQS queue empty for ${each.value.sqs_scaling_config.scale_down_evaluation_periods * each.value.sqs_scaling_config.scale_down_period / 60} minutes"

  dimensions = {
    QueueName = each.value.sqs_scaling_config.queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.sqs_scale_down[each.key].arn]

  tags = merge({
    Name    = "${var.stack_name}-${var.env}-${each.value.name}-sqs-low-alarm"
    Purpose = "ECS autoscaling based on SQS queue depth"
  }, var.additional_tags)
}

# ============================================================================
# STEP SCALING POLICIES
# ============================================================================

# Scale Up Policy - Add 1 task when alarm triggered
resource "aws_appautoscaling_policy" "sqs_scale_up" {
  for_each = { for svc in var.ecs_services : svc.name => svc if svc.sqs_scaling_config != null }

  name               = "${each.value.name}-sqs-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.scale_out_cooldown
    metric_aggregation_type = "Average"

    # Add 1 task when threshold is breached
    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

# Scale Down Policy - Remove 1 task when alarm triggered
resource "aws_appautoscaling_policy" "sqs_scale_down" {
  for_each = { for svc in var.ecs_services : svc.name => svc if svc.sqs_scaling_config != null }

  name               = "${each.value.name}-sqs-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.scale_in_cooldown
    metric_aggregation_type = "Average"

    # Remove 1 task when threshold is breached (min_capacity enforced by target)
    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}
