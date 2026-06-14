output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "service_ids" {
  description = "Map of service names to their IDs"
  value = {
    for service_name, service in aws_ecs_service.app : service_name => service.id
  }
}

output "service_arns" {
  description = "Map of service names to their ARNs"
  value = {
    for service_name, service in aws_ecs_service.app : service_name => service.id
  }
}

output "task_definition_arns" {
  description = "Map of service names to their task definition ARNs"
  value = {
    for service_name, task_def in aws_ecs_task_definition.app : service_name => task_def.arn
  }
}

output "task_definition_families" {
  description = "Map of service names to their task definition families"
  value = {
    for service_name, task_def in aws_ecs_task_definition.app : service_name => task_def.family
  }
}

output "log_group_names" {
  description = "Map of service names to their CloudWatch log group names"
  value = {
    for service_name, log_group in aws_cloudwatch_log_group.app : service_name => log_group.name
  }
}

output "log_group_arns" {
  description = "Map of service names to their CloudWatch log group ARNs"
  value = {
    for service_name, log_group in aws_cloudwatch_log_group.app : service_name => log_group.arn
  }
}

output "service_discovery_namespace_id" {
  description = "Service discovery namespace ID (if enabled)"
  value       = var.enable_service_discovery ? aws_service_discovery_private_dns_namespace.main[0].id : null
}

output "service_discovery_namespace_arn" {
  description = "Service discovery namespace ARN (if enabled)"
  value       = var.enable_service_discovery ? aws_service_discovery_private_dns_namespace.main[0].arn : null
}

output "service_discovery_service_arns" {
  description = "Map of service names to their service discovery ARNs (if enabled)"
  value = var.enable_service_discovery ? {
    for service_name, discovery_service in aws_service_discovery_service.app : service_name => discovery_service.arn
  } : {}
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

