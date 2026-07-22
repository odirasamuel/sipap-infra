# Outputs for Lambda Layers Module

# ==============================================================================
# MCP Handler Layer Outputs
# ==============================================================================

output "mcp_handler_layer_arn" {
  description = "ARN of the MCP handler Lambda layer"
  value       = var.create_mcp_handler_layer ? aws_lambda_layer_version.sipap_serverless_mcp_handler[0].arn : null
}

output "mcp_handler_layer_version" {
  description = "Version of the MCP handler Lambda layer"
  value       = var.create_mcp_handler_layer ? aws_lambda_layer_version.sipap_serverless_mcp_handler[0].version : null
}

output "mcp_handler_layer_source_hash" {
  description = "Source code hash of the MCP handler layer"
  value       = var.create_mcp_handler_layer ? aws_lambda_layer_version.sipap_serverless_mcp_handler[0].source_code_hash : null
}

# ==============================================================================
# Dependencies Layer Outputs
# ==============================================================================

output "dependencies_layer_arn" {
  description = "ARN of the dependencies Lambda layer"
  value       = var.create_dependencies_layer ? aws_lambda_layer_version.sipap_dependencies[0].arn : null
}

output "dependencies_layer_version" {
  description = "Version of the dependencies Lambda layer"
  value       = var.create_dependencies_layer ? aws_lambda_layer_version.sipap_dependencies[0].version : null
}

output "dependencies_layer_source_hash" {
  description = "Source code hash of the dependencies layer"
  value       = var.create_dependencies_layer ? aws_lambda_layer_version.sipap_dependencies[0].source_code_hash : null
}
