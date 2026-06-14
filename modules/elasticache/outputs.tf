# Outputs work for both ElastiCache Serverless and standard instances

output "cache_name" {
  description = "Name of the ElastiCache cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].name : aws_elasticache_cluster.this[0].cluster_id
}

output "cache_arn" {
  description = "ARN of the ElastiCache cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].arn : aws_elasticache_cluster.this[0].arn
}

output "cache_id" {
  description = "ID of the ElastiCache cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].id : aws_elasticache_cluster.this[0].id
}

output "endpoint" {
  description = "Endpoint configuration for the cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].endpoint : null
  sensitive   = true
}

output "reader_endpoint" {
  description = "Reader endpoint configuration (Serverless only)"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].reader_endpoint : null
  sensitive   = true
}

output "cache_nodes" {
  description = "Cache nodes (standard instance only)"
  value       = var.use_serverless ? null : aws_elasticache_cluster.this[0].cache_nodes
  sensitive   = true
}

output "configuration_endpoint" {
  description = "Configuration endpoint address (standard instance only)"
  value       = var.use_serverless ? null : (length(aws_elasticache_cluster.this[0].cache_nodes) > 0 ? aws_elasticache_cluster.this[0].cache_nodes[0].address : null)
  sensitive   = true
}

output "port" {
  description = "Port number for cache access"
  value       = var.use_serverless ? null : (length(aws_elasticache_cluster.this[0].cache_nodes) > 0 ? aws_elasticache_cluster.this[0].cache_nodes[0].port : null)
}

output "engine" {
  description = "Cache engine"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].engine : aws_elasticache_cluster.this[0].engine
}

output "engine_version" {
  description = "Engine version of the cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].full_engine_version : aws_elasticache_cluster.this[0].engine_version
}

output "security_group_ids" {
  description = "List of security group IDs associated with the cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].security_group_ids : aws_elasticache_cluster.this[0].security_group_ids
}

output "subnet_group_name" {
  description = "Name of the subnet group"
  value       = aws_elasticache_subnet_group.this.name
}

output "subnet_group_arn" {
  description = "ARN of the subnet group"
  value       = aws_elasticache_subnet_group.this.arn
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].subnet_ids : var.subnet_ids
}

output "status" {
  description = "Current status of the cache"
  value       = var.use_serverless ? aws_elasticache_serverless_cache.this[0].status : aws_elasticache_cluster.this[0].cluster_address
}

output "mode" {
  description = "Cache mode (Serverless or Standard Instance)"
  value       = var.use_serverless ? "ElastiCache Serverless" : "Standard Instance (${var.node_type})"
}
