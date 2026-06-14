output "internal_function_arn" {
  description = "ARN of the internal MCP server Lambda function"
  value       = var.create_internal_function ? aws_lambda_function.internal_mcp_server[0].arn : null
}

output "internal_function_name" {
  description = "Name of the internal MCP server Lambda function"
  value       = var.create_internal_function ? aws_lambda_function.internal_mcp_server[0].function_name : null
}

output "internal_function_invoke_arn" {
  description = "Invoke ARN of the internal MCP server Lambda function"
  value       = var.create_internal_function ? aws_lambda_function.internal_mcp_server[0].invoke_arn : null
}

output "external_function_arn" {
  description = "ARN of the external MCP server Lambda function"
  value       = var.create_external_function ? aws_lambda_function.external_mcp_server[0].arn : null
}

output "external_function_name" {
  description = "Name of the external MCP server Lambda function"
  value       = var.create_external_function ? aws_lambda_function.external_mcp_server[0].function_name : null
}

output "external_function_invoke_arn" {
  description = "Invoke ARN of the external MCP server Lambda function"
  value       = var.create_external_function ? aws_lambda_function.external_mcp_server[0].invoke_arn : null
}

# Function URL outputs
output "internal_function_url" {
  description = "Function URL of the internal MCP server Lambda function"
  value       = var.create_internal_function && var.enable_function_url ? aws_lambda_function_url.internal_function_url[0].function_url : null
}

output "external_function_url" {
  description = "Function URL of the external MCP server Lambda function"
  value       = var.create_external_function && var.enable_function_url ? aws_lambda_function_url.external_function_url[0].function_url : null
}

# SSM Parameter outputs
output "internal_ssm_parameter_name" {
  description = "Name of the SSM parameter for internal function URL"
  value       = var.create_internal_function && var.enable_function_url && var.create_ssm_parameter ? aws_ssm_parameter.internal_function_url[0].name : null
}

output "internal_ssm_parameter_arn" {
  description = "ARN of the SSM parameter for internal function URL"
  value       = var.create_internal_function && var.enable_function_url && var.create_ssm_parameter ? aws_ssm_parameter.internal_function_url[0].arn : null
}

output "external_ssm_parameter_name" {
  description = "Name of the SSM parameter for external function URL"
  value       = var.create_external_function && var.enable_function_url && var.create_ssm_parameter_external ? aws_ssm_parameter.external_function_url[0].name : null
}

output "external_ssm_parameter_arn" {
  description = "ARN of the SSM parameter for external function URL"
  value       = var.create_external_function && var.enable_function_url && var.create_ssm_parameter_external ? aws_ssm_parameter.external_function_url[0].arn : null
}

