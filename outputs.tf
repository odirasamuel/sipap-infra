# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.subnets.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.subnets.private_subnet_ids
}

# Database Outputs (Aurora Serverless v2 or Standard RDS)
output "aurora_cluster_endpoint" {
  description = "Database endpoint (Aurora or Standard RDS)"
  value       = module.aurora.endpoint
  sensitive   = true
}

output "aurora_database_name" {
  description = "Database name"
  value       = module.aurora.database_name
}

output "aurora_password_secret_arn" {
  description = "ARN of database password in Secrets Manager"
  value       = module.aurora.password_secret_arn
}

output "database_mode" {
  description = "Database mode (Serverless v2 or Standard Instance)"
  value       = module.aurora.mode
}

# ElastiCache Outputs (Serverless or Standard Instance)
output "elasticache_endpoint" {
  description = "ElastiCache endpoint (Serverless or Standard)"
  value       = module.elasticache.endpoint
  sensitive   = true
}

output "elasticache_reader_endpoint" {
  description = "ElastiCache reader endpoint (Serverless only)"
  value       = module.elasticache.reader_endpoint
  sensitive   = true
}

output "elasticache_configuration_endpoint" {
  description = "ElastiCache configuration endpoint (Standard instance only)"
  value       = module.elasticache.configuration_endpoint
  sensitive   = true
}

output "cache_mode" {
  description = "Cache mode (Serverless or Standard Instance)"
  value       = module.elasticache.mode
}

# ECR Outputs
output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

# SQS Outputs
output "prediction_queue_url" {
  description = "SQS prediction queue URL"
  value       = aws_sqs_queue.prediction_queue.url
}

output "prediction_dlq_url" {
  description = "SQS prediction DLQ URL"
  value       = aws_sqs_queue.prediction_dlq.url
}

# Secrets Manager Outputs
output "aurora_credentials_secret_arn" {
  description = "ARN of Aurora credentials secret"
  value       = module.aurora_credentials_secret.secret_arn
  sensitive   = true
}

output "api_keys_secret_arn" {
  description = "ARN of API keys secret"
  value       = module.api_keys_secret.secret_arn
}

output "api_keys_secret_name" {
  description = "Name of API keys secret (for CLI population)"
  value       = module.api_keys_secret.secret_name
}

output "populate_api_keys_cli_command" {
  description = "AWS CLI command to populate API keys secret (use profile odiraaws)"
  value       = <<-EOT
    aws secretsmanager put-secret-value \
      --secret-id ${module.api_keys_secret.secret_name} \
      --secret-string '{"FOOTBALL_DATA_KEY":"your_key_here","ODDS_API_KEY":"your_key_here","THESPORTSDB_KEY":"123"}' \
      --profile odiraaws \
      --region ${var.aws_region}
  EOT
}

# Security Group Outputs
output "elasticache_sg_id" {
  description = "ElastiCache security group ID"
  value       = module.elasticache_sg.security_group_id
}

output "ecs_tasks_sg_id" {
  description = "ECS tasks security group ID"
  value       = module.ecs_tasks_sg.security_group_id
}

# IAM Role Outputs
output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.ecs_task_execution_role.role_arn
}

output "sqs_sender_role_arn" {
  description = "SQS sender role ARN"
  value       = module.sqs_sender_role.role_arn
}

# ==============================================================================
# NOTE: Lambda MCP outputs are in core_deploy/ (separate root module)
# ==============================================================================
# To see Lambda MCP outputs:
#   cd core_deploy
#   terraform output
# ==============================================================================
