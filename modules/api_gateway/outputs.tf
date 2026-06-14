# Gateway Information
output "gateway_id" {
  description = "ID of the API Gateway"
  value = local.is_rest_api ? (
    length(aws_api_gateway_rest_api.main) > 0 ? aws_api_gateway_rest_api.main[0].id : null
    ) : (
    length(aws_apigatewayv2_api.main) > 0 ? aws_apigatewayv2_api.main[0].id : null
  )
}

output "gateway_name" {
  description = "Name of the API Gateway"
  value       = var.gateway_name
}

output "gateway_type" {
  description = "Type of the API Gateway"
  value       = var.gateway_type
}

# API URLs
output "invoke_url" {
  description = "Invoke URL of the API Gateway"
  value = local.is_rest_api ? (
    length(aws_api_gateway_stage.main) > 0 ? aws_api_gateway_stage.main[0].invoke_url : null
    ) : (
    length(aws_apigatewayv2_stage.main) > 0 ? aws_apigatewayv2_stage.main[0].invoke_url : null
  )
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway"
  value = local.is_rest_api ? (
    length(aws_api_gateway_rest_api.main) > 0 ? aws_api_gateway_rest_api.main[0].execution_arn : null
    ) : (
    length(aws_apigatewayv2_api.main) > 0 ? aws_apigatewayv2_api.main[0].execution_arn : null
  )
}

# Stage Information
output "stage_name" {
  description = "Name of the deployment stage"
  value       = var.stage_name
}

output "stage_arn" {
  description = "ARN of the deployment stage"
  value = local.is_rest_api ? (
    length(aws_api_gateway_stage.main) > 0 ? aws_api_gateway_stage.main[0].arn : null
    ) : (
    length(aws_apigatewayv2_stage.main) > 0 ? aws_apigatewayv2_stage.main[0].arn : null
  )
}

# REST API Specific Outputs
output "rest_api_id" {
  description = "ID of the REST API (only available for REST API type)"
  value       = local.is_rest_api && length(aws_api_gateway_rest_api.main) > 0 ? aws_api_gateway_rest_api.main[0].id : null
}

output "root_resource_id" {
  description = "Root resource ID of the REST API (only available for REST API type)"
  value       = local.is_rest_api && length(aws_api_gateway_rest_api.main) > 0 ? aws_api_gateway_rest_api.main[0].root_resource_id : null
}

output "deployment_id" {
  description = "ID of the deployment (only available for REST API type)"
  value       = local.is_rest_api && length(aws_api_gateway_deployment.main) > 0 ? aws_api_gateway_deployment.main[0].id : null
}

# HTTP API Specific Outputs
output "http_api_id" {
  description = "ID of the HTTP API (only available for HTTP API type)"
  value       = local.is_http_api && length(aws_apigatewayv2_api.main) > 0 ? aws_apigatewayv2_api.main[0].id : null
}

output "http_api_endpoint" {
  description = "API endpoint URL (only available for HTTP API type)"
  value       = local.is_http_api && length(aws_apigatewayv2_api.main) > 0 ? aws_apigatewayv2_api.main[0].api_endpoint : null
}

# Usage Plan and API Key Outputs (REST API only)
output "usage_plan_id" {
  description = "ID of the usage plan (only available for REST API with usage plan enabled)"
  value       = local.is_rest_api && var.create_usage_plan && length(aws_api_gateway_usage_plan.main) > 0 ? aws_api_gateway_usage_plan.main[0].id : null
}

output "usage_plan_arn" {
  description = "ARN of the usage plan (only available for REST API with usage plan enabled)"
  value       = local.is_rest_api && var.create_usage_plan && length(aws_api_gateway_usage_plan.main) > 0 ? aws_api_gateway_usage_plan.main[0].arn : null
}

output "api_key_id" {
  description = "ID of the API key (only available when API key is created)"
  value       = local.is_rest_api && var.create_api_key && length(aws_api_gateway_api_key.main) > 0 ? aws_api_gateway_api_key.main[0].id : null
}

output "api_key_value" {
  description = "Value of the API key (sensitive, only available when API key is created)"
  value       = local.is_rest_api && var.create_api_key && length(aws_api_gateway_api_key.main) > 0 ? aws_api_gateway_api_key.main[0].value : null
  sensitive   = true
}

# Integration Information
output "integration_type" {
  description = "Type of integration configured"
  value       = var.integration_type
}

output "sqs_queue_name" {
  description = "Name of the SQS queue (only available for SQS integration)"
  value       = local.is_sqs_integration ? local.sqs_queue_name : null
}

output "lambda_function_name" {
  description = "Name of the Lambda function (only available for Lambda integration)"
  value       = local.is_lambda_integration ? var.lambda_function_name : null
}

# Route Information (HTTP API only)
output "configured_routes" {
  description = "List of configured routes (only available for HTTP API)"
  value       = local.is_http_api ? var.routes : null
}

# Observability Outputs
output "execution_log_group_name" {
  description = "Name of CloudWatch Log Group for execution logs"
  value       = var.enable_execution_logs && length(aws_cloudwatch_log_group.execution_logs) > 0 ? aws_cloudwatch_log_group.execution_logs[0].name : null
}

output "execution_log_group_arn" {
  description = "ARN of CloudWatch Log Group for execution logs"
  value       = var.enable_execution_logs && length(aws_cloudwatch_log_group.execution_logs) > 0 ? aws_cloudwatch_log_group.execution_logs[0].arn : null
}

output "access_log_group_name" {
  description = "Name of CloudWatch Log Group for access logs"
  value       = var.enable_access_logging && length(aws_cloudwatch_log_group.access_logs) > 0 ? aws_cloudwatch_log_group.access_logs[0].name : null
}

output "access_log_group_arn" {
  description = "ARN of CloudWatch Log Group for access logs"
  value       = var.enable_access_logging && length(aws_cloudwatch_log_group.access_logs) > 0 ? aws_cloudwatch_log_group.access_logs[0].arn : null
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray_tracing
}

output "observability_status" {
  description = "Summary of observability features status"
  value = {
    execution_logs   = var.enable_execution_logs
    access_logs      = var.enable_access_logging
    detailed_metrics = var.enable_detailed_metrics
    xray_tracing     = var.enable_xray_tracing
    data_trace       = var.enable_data_trace
    logging_level    = var.logging_level
  }
}

output "ssm_parameter_name" {
  description = "Name of the SSM parameter"
  value       = local.is_http_api && var.create_ssm_parameter && length(module.ssm_parameter) > 0 ? module.ssm_parameter[0].parameter_name : null
}

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter"
  value       = local.is_http_api && var.create_ssm_parameter && length(module.ssm_parameter) > 0 ? module.ssm_parameter[0].parameter_arn : null
}

output "ssm_parameter_version" {
  description = "Version of the SSM parameter"
  value       = local.is_http_api && var.create_ssm_parameter && length(module.ssm_parameter) > 0 ? module.ssm_parameter[0].parameter_version : null
}

output "primary_route" {
  description = "Primary route used for SSM parameter endpoint URL"
  value       = local.is_http_api ? local.primary_route : null
}

# ============================================================================
# Custom Domain Outputs
# ============================================================================

output "custom_domain_enabled" {
  description = "Whether custom domain is enabled"
  value       = var.enable_custom_domain
}

output "custom_domain_name" {
  description = "Custom domain name configured for this API Gateway"
  value       = var.enable_custom_domain ? var.custom_domain_name : null
}

output "custom_domain_regional_domain" {
  description = "Regional domain name for DNS configuration (CNAME/ALIAS target)"
  value = var.enable_custom_domain ? (
    local.is_http_api && length(aws_apigatewayv2_domain_name.main) > 0 ? (
      aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].target_domain_name
      ) : (
      local.is_rest_api && length(aws_api_gateway_domain_name.main) > 0 ? (
        aws_api_gateway_domain_name.main[0].regional_domain_name
      ) : null
    )
  ) : null
}

output "custom_domain_regional_hosted_zone_id" {
  description = "Regional hosted zone ID for Route53 ALIAS record configuration"
  value = var.enable_custom_domain ? (
    local.is_http_api && length(aws_apigatewayv2_domain_name.main) > 0 ? (
      aws_apigatewayv2_domain_name.main[0].domain_name_configuration[0].hosted_zone_id
      ) : (
      local.is_rest_api && length(aws_api_gateway_domain_name.main) > 0 ? (
        aws_api_gateway_domain_name.main[0].regional_zone_id
      ) : null
    )
  ) : null
}

output "custom_domain_base_path" {
  description = "Base path configured for the custom domain mapping"
  value       = var.enable_custom_domain ? var.custom_domain_base_path : null
}

output "custom_domain_url" {
  description = "Full custom domain URL (including base path if configured)"
  value = var.enable_custom_domain ? (
    var.custom_domain_base_path != "" ?
    "https://${var.custom_domain_name}/${var.custom_domain_base_path}" :
    "https://${var.custom_domain_name}"
  ) : null
}