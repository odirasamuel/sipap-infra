# Outputs work for both Aurora Serverless v2 and standard RDS

output "endpoint" {
  description = "Database endpoint (works for both Aurora and standard RDS)"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].endpoint : aws_db_instance.standard[0].address
  sensitive   = true
}

output "reader_endpoint" {
  description = "Reader endpoint (Aurora only, null for standard RDS)"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].reader_endpoint : null
  sensitive   = true
}

output "database_name" {
  description = "Name of the default database"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].database_name : aws_db_instance.standard[0].db_name
}

output "master_username" {
  description = "Master username"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].master_username : aws_db_instance.standard[0].username
  sensitive   = true
}

output "password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the database password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "port" {
  description = "Database port"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].port : aws_db_instance.standard[0].port
}

output "db_instance_id" {
  description = "Database instance identifier"
  value       = var.use_serverless ? aws_rds_cluster.aurora[0].cluster_identifier : aws_db_instance.standard[0].identifier
}

output "mode" {
  description = "Database mode (Serverless v2 or Standard Instance)"
  value       = var.use_serverless ? "Aurora Serverless v2" : "Standard RDS Instance (${var.instance_class})"
}
