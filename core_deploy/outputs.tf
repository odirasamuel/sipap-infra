# Outputs for SIPAP Core Deployment
# Lambda MCP Function URLs and related outputs

# ==============================================================================
# Data MCP Outputs
# ==============================================================================

output "data_mcp_function_arn" {
  description = "ARN of the Data MCP Lambda function"
  value       = module.data_mcp_lambda_internal.internal_function_arn
}

output "data_mcp_function_name" {
  description = "Name of the Data MCP Lambda function"
  value       = module.data_mcp_lambda_internal.internal_function_name
}

output "data_mcp_function_url" {
  description = "Function URL of the Data MCP Lambda function"
  value       = module.data_mcp_lambda_internal.internal_function_url
}

output "data_mcp_ssm_parameter_name" {
  description = "SSM parameter name containing Data MCP endpoint configuration"
  value       = module.data_mcp_lambda_internal.internal_ssm_parameter_name
}

# ==============================================================================
# Intelligence MCP Outputs
# ==============================================================================

output "intelligence_mcp_function_arn" {
  description = "ARN of the Intelligence MCP Lambda function"
  value       = module.intelligence_mcp_lambda_internal.internal_function_arn
}

output "intelligence_mcp_function_name" {
  description = "Name of the Intelligence MCP Lambda function"
  value       = module.intelligence_mcp_lambda_internal.internal_function_name
}

output "intelligence_mcp_function_url" {
  description = "Function URL of the Intelligence MCP Lambda function"
  value       = module.intelligence_mcp_lambda_internal.internal_function_url
}

output "intelligence_mcp_ssm_parameter_name" {
  description = "SSM parameter name containing Intelligence MCP endpoint configuration"
  value       = module.intelligence_mcp_lambda_internal.internal_ssm_parameter_name
}

# ==============================================================================
# IAM Role Outputs
# ==============================================================================

output "mcp_servers_role_arn" {
  description = "IAM role ARN for MCP Lambda servers"
  value       = module.mcp_servers_role.role_arn
}

output "mcp_servers_role_name" {
  description = "IAM role name for MCP Lambda servers"
  value       = module.mcp_servers_role.role_name
}

# ==============================================================================
# Security Group Outputs
# ==============================================================================

output "lambda_internal_security_group_id" {
  description = "Security group ID for Lambda internal functions"
  value       = module.lambda_internal_security_group.security_group_id
}

# ==============================================================================
# Lambda Layer Outputs
# ==============================================================================

output "shared_mcp_handler_layer_arn" {
  description = "ARN of the shared MCP handler layer"
  value       = module.shared_mcp_handler_layer.mcp_handler_layer_arn
}

output "common_layer_arn" {
  description = "ARN of the common utilities layer"
  value       = module.common_layer.dependencies_layer_arn
}

output "data_mcp_dependencies_layer_arn" {
  description = "ARN of the Data MCP dependencies layer"
  value       = module.data_mcp_lambda_layers.dependencies_layer_arn
}

output "intelligence_mcp_dependencies_layer_arn" {
  description = "ARN of the Intelligence MCP dependencies layer"
  value       = module.intelligence_mcp_lambda_layers.dependencies_layer_arn
}

# ==============================================================================
# Bedrock Inference Profile Outputs
# ==============================================================================

output "bedrock_orchestrator_profile_arn" {
  description = "ARN of the Bedrock Inference Profile for orchestrator"
  value       = aws_bedrock_inference_profile.orchestrator.arn
}

output "bedrock_orchestrator_profile_id" {
  description = "ID of the Bedrock Inference Profile for orchestrator"
  value       = aws_bedrock_inference_profile.orchestrator.id
}

output "bedrock_intelligence_mcp_profile_arn" {
  description = "ARN of the Bedrock Inference Profile for intelligence-mcp"
  value       = aws_bedrock_inference_profile.intelligence_mcp.arn
}

output "bedrock_intelligence_mcp_profile_id" {
  description = "ID of the Bedrock Inference Profile for intelligence-mcp"
  value       = aws_bedrock_inference_profile.intelligence_mcp.id
}

# ==============================================================================
# SQS Queue Outputs
# ==============================================================================

output "whatsapp_queue_url" {
  description = "URL of the WhatsApp messages SQS queue"
  value       = module.whatsapp_sqs.queue_url
}

output "whatsapp_queue_arn" {
  description = "ARN of the WhatsApp messages SQS queue"
  value       = module.whatsapp_sqs.queue_arn
}

output "whatsapp_queue_name" {
  description = "Name of the WhatsApp messages SQS queue"
  value       = module.whatsapp_sqs.queue_name
}

output "whatsapp_dlq_url" {
  description = "URL of the WhatsApp messages DLQ"
  value       = module.whatsapp_sqs.dlq_url
}

output "whatsapp_dlq_arn" {
  description = "ARN of the WhatsApp messages DLQ"
  value       = module.whatsapp_sqs.dlq_arn
}

output "whatsapp_dlq_name" {
  description = "Name of the WhatsApp messages DLQ"
  value       = module.whatsapp_sqs.dlq_name
}

# ==============================================================================
# API Gateway Outputs
# ==============================================================================

output "whatsapp_api_gateway_id" {
  description = "ID of the WhatsApp webhook API Gateway"
  value       = module.whatsapp_api_gateway.api_gateway_id
}

output "whatsapp_api_gateway_url" {
  description = "Invoke URL of the WhatsApp webhook API Gateway (use for Twilio webhook configuration)"
  value       = module.whatsapp_api_gateway.api_gateway_url
}

output "whatsapp_api_gateway_api_key_id" {
  description = "ID of the Twilio webhook API key"
  value       = module.whatsapp_api_gateway.api_key_id
}

output "whatsapp_api_gateway_api_key_value" {
  description = "Value of the Twilio webhook API key (sensitive)"
  value       = module.whatsapp_api_gateway.api_key_value
  sensitive   = true
}

output "api_gateway_sqs_role_arn" {
  description = "ARN of the IAM role for API Gateway → SQS integration"
  value       = module.whatsapp_api_gateway.api_gateway_sqs_role_arn
}

# ==============================================================================
# Orchestrator Task Role Outputs
# ==============================================================================

output "orchestrator_task_role_arn" {
  description = "ARN of the orchestrator ECS task role"
  value       = module.orchestrator_task_role.role_arn
}

output "orchestrator_task_role_name" {
  description = "Name of the orchestrator ECS task role"
  value       = module.orchestrator_task_role.role_name
}

output "orchestrator_security_group_id" {
  description = "Security group ID for orchestrator ECS service"
  value       = module.orchestrator_security_group.security_group_id
}

# ==============================================================================
# WhatsApp Auth Lambda Outputs
# ==============================================================================

output "whatsapp_auth_function_name" {
  description = "Name of the WhatsApp auth handler Lambda function"
  value       = module.whatsapp_auth_lambda.function_name
}

output "whatsapp_auth_function_arn" {
  description = "ARN of the WhatsApp auth handler Lambda function"
  value       = module.whatsapp_auth_lambda.function_arn
}

output "whatsapp_auth_log_group_name" {
  description = "CloudWatch log group name for WhatsApp auth handler"
  value       = module.whatsapp_auth_lambda.log_group_name
}

output "whatsapp_auth_enabled" {
  description = "Whether WhatsApp authentication is enabled (API Gateway routes through Lambda)"
  value       = var.enable_whatsapp_auth
}
