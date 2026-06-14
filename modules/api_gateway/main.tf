# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values for computed configurations
locals {
  is_rest_api                = var.gateway_type == "rest_api"
  is_http_api                = var.gateway_type == "http_api"
  is_sqs_integration         = var.integration_type == "sqs"
  is_lambda_integration      = var.integration_type == "lambda"
  is_lambda_rest_integration = local.is_lambda_integration && local.is_rest_api
  is_lambda_http_integration = local.is_lambda_integration && local.is_http_api

  # Default names if not provided
  usage_plan_name = var.usage_plan_name != "" ? var.usage_plan_name : "${var.gateway_name}-usage-plan"
  api_key_name    = var.api_key_name != "" ? var.api_key_name : "${var.gateway_name}-api-key"

  # SQS queue name from ARN
  sqs_queue_name = local.is_sqs_integration ? split(":", var.sqs_queue_arn)[5] : ""

  common_tags = merge({
    Name  = var.gateway_name
    Owner = "sentinel-automation"
  }, var.additional_tags)

  # Access log format - default comprehensive JSON format
  default_access_log_format = jsonencode({
    requestId               = "$context.requestId"
    sourceIp                = "$context.identity.sourceIp"
    requestTime             = "$context.requestTime"
    protocol                = "$context.protocol"
    httpMethod              = "$context.httpMethod"
    resourcePath            = "$context.resourcePath"
    routeKey                = "$context.routeKey"
    status                  = "$context.status"
    responseLength          = "$context.responseLength"
    integrationErrorMessage = "$context.integrationErrorMessage"
    errorMessage            = "$context.error.message"
    integrationStatus       = "$context.integrationStatus"
    integrationLatency      = "$context.integrationLatency"
    responseLatency         = "$context.responseLatency"
  })

  access_log_format_final = var.access_log_format != "" ? var.access_log_format : local.default_access_log_format

  # SSM Parameter Store configuration
  # Determine primary route (first POST route, or first route if no POST)
  primary_route = local.is_http_api && length(var.routes) > 0 ? (
    try(
      [for route in var.routes : route.path if route.method == "POST"][0],
      var.routes[0].path
    )
  ) : ""

  # Construct full endpoint URL with primary route
  full_endpoint_url = local.is_http_api && var.create_ssm_parameter ? (
    length(aws_apigatewayv2_stage.main) > 0 && local.primary_route != "" ?
    "${trimsuffix(aws_apigatewayv2_stage.main[0].invoke_url, "/")}${local.primary_route}" :
    ""
  ) : ""

  # SSM parameter name
  ssm_parameter_name = local.is_http_api && var.create_ssm_parameter ? (
    var.ssm_parameter_name_override != "" ?
    var.ssm_parameter_name_override :
    "/sre/sentinel-mcp-${var.ssm_service_identifier}"
  ) : ""

  # JSON-formatted parameter value
  ssm_parameter_value = local.is_http_api && var.create_ssm_parameter && local.full_endpoint_url != "" ? jsonencode({
    "${upper(var.ssm_service_identifier)}_MCP_URL"     = local.full_endpoint_url
    "${upper(var.ssm_service_identifier)}_MCP_TIMEOUT" = var.ssm_mcp_timeout
  }) : ""
}

# REST API Gateway (for SQS integrations primarily)
resource "aws_api_gateway_rest_api" "main" {
  count = local.is_rest_api ? 1 : 0

  name        = var.gateway_name
  description = var.description

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  policy = var.endpoint_type == "PRIVATE" ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "*"
      }
    ]
  }) : null

  tags = local.common_tags
}

# HTTP API Gateway (for Lambda integrations primarily)  
resource "aws_apigatewayv2_api" "main" {
  count = local.is_http_api ? 1 : 0

  name          = var.gateway_name
  description   = var.description
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]
    expose_headers    = []
    max_age           = 0
  }

  tags = local.common_tags
}

# CloudWatch Log Groups for API Gateway Observability
resource "aws_cloudwatch_log_group" "execution_logs" {
  count = var.enable_execution_logs ? 1 : 0

  name              = "/aws/apigateway/${var.gateway_name}/execution-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.gateway_name}-execution-logs"
  })
}

resource "aws_cloudwatch_log_group" "access_logs" {
  count = var.enable_access_logging ? 1 : 0

  name              = "/aws/apigateway/${var.gateway_name}/access-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.gateway_name}-access-logs"
  })
}

# REST API Resources and Methods (for SQS)
resource "aws_api_gateway_resource" "send" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  parent_id   = aws_api_gateway_rest_api.main[0].root_resource_id
  path_part   = "send"
}

resource "aws_api_gateway_method" "send_post" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id      = aws_api_gateway_rest_api.main[0].id
  resource_id      = aws_api_gateway_resource.send[0].id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.header.Content-Type"  = false
    "method.request.querystring.QueueUrl" = false
  }
}

# SQS Integration for REST API
resource "aws_api_gateway_integration" "sqs" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.send[0].id
  http_method = aws_api_gateway_method.send_post[0].http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.sqs_region != "" ? var.sqs_region : data.aws_region.current.name}:sqs:action/SendMessage"
  credentials             = var.sqs_execution_role_arn

  cache_key_parameters = [
    "method.request.querystring.QueueUrl",
    "method.request.header.Content-Type"
  ]
  cache_namespace = "sqs-integration"

  request_parameters = {
    "integration.request.header.Content-Type"  = "'application/x-www-form-urlencoded'"
    "integration.request.querystring.QueueUrl" = "'https://sqs.${var.sqs_region != "" ? var.sqs_region : data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${local.sqs_queue_name}'"
  }

  request_templates = {
    # "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)&MessageGroupId=${var.sqs_message_group_id}&MessageDeduplicationId=$context.requestId"
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$input.path('$.hostname')&MessageDeduplicationId=$context.requestId"
  }

  passthrough_behavior = "WHEN_NO_TEMPLATES"
  timeout_milliseconds = 29000
}

# Method Response for SQS Integration
resource "aws_api_gateway_method_response" "sqs_200" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.send[0].id
  http_method = aws_api_gateway_method.send_post[0].http_method
  status_code = "200"
}

# Integration Response for SQS
resource "aws_api_gateway_integration_response" "sqs_200" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.send[0].id
  http_method = aws_api_gateway_method.send_post[0].http_method
  status_code = aws_api_gateway_method_response.sqs_200[0].status_code

  response_templates = {
    "application/json" = jsonencode({
      message   = "Message sent successfully"
      requestId = "$context.requestId"
    })
  }

  depends_on = [
    aws_api_gateway_integration.sqs
  ]
}

# Lambda Integration for HTTP API
resource "aws_apigatewayv2_integration" "lambda" {
  count = local.is_lambda_http_integration ? 1 : 0

  api_id = aws_apigatewayv2_api.main[0].id

  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = var.lambda_function_arn

  timeout_milliseconds = 29000
}

# HTTP API Routes for Lambda
resource "aws_apigatewayv2_route" "lambda_routes" {
  count = local.is_lambda_http_integration ? length(var.routes) : 0

  api_id = aws_apigatewayv2_api.main[0].id

  route_key = "${var.routes[count.index].method} ${var.routes[count.index].path}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda[0].id}"
}

# REST API Deployment
resource "aws_api_gateway_deployment" "main" {
  count = local.is_rest_api ? 1 : 0

  depends_on = [
    aws_api_gateway_method.send_post,
    aws_api_gateway_integration.sqs,
    aws_api_gateway_method_response.sqs_200,
    aws_api_gateway_integration_response.sqs_200,
    aws_api_gateway_method.lambda_methods,
    aws_api_gateway_integration.lambda_rest,
    aws_api_gateway_method_response.lambda_200,
    aws_api_gateway_integration_response.lambda_200
  ]

  rest_api_id = aws_api_gateway_rest_api.main[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.send,
      aws_api_gateway_method.send_post,
      aws_api_gateway_integration.sqs,
      aws_api_gateway_resource.lambda,
      aws_api_gateway_method.lambda_methods,
      aws_api_gateway_integration.lambda_rest,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# REST API Stage
# REST API Stage with Full Observability
resource "aws_api_gateway_stage" "main" {
  count = local.is_rest_api ? 1 : 0

  deployment_id = aws_api_gateway_deployment.main[0].id
  rest_api_id   = aws_api_gateway_rest_api.main[0].id
  stage_name    = var.stage_name

  # X-Ray Tracing
  xray_tracing_enabled = var.enable_xray_tracing && var.xray_tracing_enabled

  # Access Logging
  dynamic "access_log_settings" {
    for_each = var.enable_access_logging && length(aws_cloudwatch_log_group.access_logs) > 0 ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.access_logs[0].arn
      format          = local.access_log_format_final
    }
  }

  # Caching
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"

  tags = merge(local.common_tags, {
    Name = "${var.gateway_name}-${var.stage_name}-stage"
  })

  depends_on = [
    aws_cloudwatch_log_group.access_logs
  ]
}

# Method Settings with Enhanced Observability - Apply to all methods
resource "aws_api_gateway_method_settings" "all_methods" {
  count = local.is_rest_api && var.enable_execution_logs ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  stage_name  = aws_api_gateway_stage.main[0].stage_name
  method_path = "*/*"

  settings {
    # Execution Logging
    logging_level      = var.logging_level
    data_trace_enabled = var.enable_data_trace
    metrics_enabled    = var.enable_detailed_metrics

    # Throttling (uses stage-level settings)
    throttling_burst_limit = -1
    throttling_rate_limit  = -1
  }

  depends_on = [
    aws_api_gateway_stage.main,
    aws_cloudwatch_log_group.execution_logs
  ]
}

# Method Settings for SQS Integration (if applicable)
resource "aws_api_gateway_method_settings" "sqs_method_settings" {
  count = local.is_rest_api && local.is_sqs_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  stage_name  = aws_api_gateway_stage.main[0].stage_name
  method_path = "${aws_api_gateway_resource.send[0].path_part}/${aws_api_gateway_method.send_post[0].http_method}"

  settings {
    # Caching
    caching_enabled      = false
    cache_ttl_in_seconds = 300

    # Execution Logging
    logging_level      = var.enable_execution_logs ? var.logging_level : "OFF"
    data_trace_enabled = var.enable_data_trace
    metrics_enabled    = var.enable_detailed_metrics
  }

  depends_on = [
    aws_api_gateway_stage.main
  ]
}

# HTTP API Stage with Full Observability
resource "aws_apigatewayv2_stage" "main" {
  count = local.is_http_api ? 1 : 0

  api_id      = aws_apigatewayv2_api.main[0].id
  name        = var.stage_name
  auto_deploy = var.stage_auto_deploy

  # Access Logging
  dynamic "access_log_settings" {
    for_each = var.enable_access_logging && length(aws_cloudwatch_log_group.access_logs) > 0 ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.access_logs[0].arn
      format          = local.access_log_format_final
    }
  }

  # Default Route Settings with Enhanced Observability
  default_route_settings {
    detailed_metrics_enabled = var.enable_detailed_metrics
    logging_level            = var.enable_execution_logs ? var.logging_level : "OFF"
    data_trace_enabled       = var.enable_data_trace
    throttling_burst_limit   = 5000
    throttling_rate_limit    = 10000
  }

  tags = merge(local.common_tags, {
    Name = "${var.gateway_name}-${replace(var.stage_name, "$", "")}-stage"
  })

  depends_on = [
    aws_cloudwatch_log_group.access_logs,
    aws_cloudwatch_log_group.execution_logs
  ]
}

# Usage Plan (REST API only)
resource "aws_api_gateway_usage_plan" "main" {
  count = local.is_rest_api && var.create_usage_plan ? 1 : 0

  name        = local.usage_plan_name
  description = var.usage_plan_description != "" ? var.usage_plan_description : "Usage plan for ${var.gateway_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main[0].id
    stage  = aws_api_gateway_stage.main[0].stage_name
  }

  throttle_settings {
    rate_limit  = var.throttle_rate_limit
    burst_limit = var.throttle_burst_limit
  }

  quota_settings {
    limit  = var.quota_limit
    period = var.quota_period
  }

  tags = merge(local.common_tags, {
    Name = local.usage_plan_name
  })
}

# API Key
resource "aws_api_gateway_api_key" "main" {
  count = local.is_rest_api && var.create_api_key ? 1 : 0

  name        = local.api_key_name
  description = "API key for ${var.gateway_name}"

  tags = merge(local.common_tags, {
    Name = local.api_key_name
  })
}

# Usage Plan Key Association
resource "aws_api_gateway_usage_plan_key" "main" {
  count = local.is_rest_api && var.create_usage_plan && var.create_api_key ? 1 : 0

  key_id        = aws_api_gateway_api_key.main[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main[0].id
}

# Lambda Permission for HTTP API - individual permissions for each route
resource "aws_lambda_permission" "api_gateway_invoke" {
  count = local.is_lambda_http_integration ? length(var.routes) : 0

  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main[0].execution_arn}/*/*${var.routes[count.index].path}"
}

# REST API Resources and Methods for Lambda Integration
resource "aws_api_gateway_resource" "lambda" {
  count = local.is_lambda_rest_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  parent_id   = aws_api_gateway_rest_api.main[0].root_resource_id
  path_part   = var.lambda_rest_api_resource_path
}

resource "aws_api_gateway_method" "lambda_methods" {
  count = local.is_lambda_rest_integration ? length(var.lambda_rest_api_methods) : 0

  rest_api_id      = aws_api_gateway_rest_api.main[0].id
  resource_id      = aws_api_gateway_resource.lambda[0].id
  http_method      = var.lambda_rest_api_methods[count.index]
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.header.Content-Type" = false
  }
}

# Lambda Integration for REST API
resource "aws_api_gateway_integration" "lambda_rest" {
  count = local.is_lambda_rest_integration ? length(var.lambda_rest_api_methods) : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.lambda[0].id
  http_method = aws_api_gateway_method.lambda_methods[count.index].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_function_arn
  timeout_milliseconds    = 29000
}

# Method Response for Lambda REST API Integration
resource "aws_api_gateway_method_response" "lambda_200" {
  count = local.is_lambda_rest_integration ? length(var.lambda_rest_api_methods) : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.lambda[0].id
  http_method = aws_api_gateway_method.lambda_methods[count.index].http_method
  status_code = "200"
}

# Integration Response for Lambda REST API
resource "aws_api_gateway_integration_response" "lambda_200" {
  count = local.is_lambda_rest_integration ? length(var.lambda_rest_api_methods) : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.lambda[0].id
  http_method = aws_api_gateway_method.lambda_methods[count.index].http_method
  status_code = aws_api_gateway_method_response.lambda_200[count.index].status_code

  depends_on = [aws_api_gateway_integration.lambda_rest]
}

# Lambda Permission for REST API
resource "aws_lambda_permission" "api_gateway_invoke_rest" {
  count = local.is_lambda_rest_integration ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main[0].execution_arn}/*/*"
}

# ============================================================================
# SSM Parameter Store for HTTP API Gateway
# ============================================================================

module "ssm_parameter" {
  source = "../parameter_store"

  count = (
    local.is_http_api &&
    var.create_ssm_parameter &&
    var.ssm_service_identifier != ""
  ) ? 1 : 0

  parameter_name        = local.ssm_parameter_name
  parameter_value       = local.ssm_parameter_value
  parameter_description = "MCP API Gateway endpoint configuration for ${var.gateway_name}"
  parameter_type        = "String"
  parameter_tier        = "Standard"

  additional_tags = merge(local.common_tags, {
    APIGatewayName = var.gateway_name
    APIGatewayType = var.gateway_type
  })

  depends_on = [
    aws_apigatewayv2_stage.main,
    aws_apigatewayv2_route.lambda_routes
  ]
}

# ============================================================================
# Custom Domain Name Management
# ============================================================================

# HTTP API (v2) Custom Domain
resource "aws_apigatewayv2_domain_name" "main" {
  count = local.is_http_api && var.enable_custom_domain ? 1 : 0

  domain_name = var.custom_domain_name

  domain_name_configuration {
    certificate_arn = var.custom_domain_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = var.custom_domain_security_policy
  }

  tags = merge(local.common_tags, {
    Name = var.custom_domain_name
  })
}

# HTTP API (v2) Domain Mapping
resource "aws_apigatewayv2_api_mapping" "main" {
  count = local.is_http_api && var.enable_custom_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.main[0].id
  domain_name = aws_apigatewayv2_domain_name.main[0].id
  stage       = aws_apigatewayv2_stage.main[0].id

  # Optional: Add base path if specified (e.g., /v1, /api)
  api_mapping_key = var.custom_domain_base_path != "" ? var.custom_domain_base_path : null

  depends_on = [
    aws_apigatewayv2_stage.main,
    aws_apigatewayv2_domain_name.main
  ]
}

# REST API Custom Domain
resource "aws_api_gateway_domain_name" "main" {
  count = local.is_rest_api && var.enable_custom_domain ? 1 : 0

  domain_name              = var.custom_domain_name
  regional_certificate_arn = var.custom_domain_certificate_arn
  security_policy          = var.custom_domain_security_policy

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name = var.custom_domain_name
  })
}

# REST API Base Path Mapping
resource "aws_api_gateway_base_path_mapping" "main" {
  count = local.is_rest_api && var.enable_custom_domain ? 1 : 0

  api_id      = aws_api_gateway_rest_api.main[0].id
  domain_name = aws_api_gateway_domain_name.main[0].domain_name
  stage_name  = aws_api_gateway_stage.main[0].stage_name

  # Optional: Add base path if specified (e.g., /v1, /api)
  base_path = var.custom_domain_base_path != "" ? var.custom_domain_base_path : null

  depends_on = [
    aws_api_gateway_stage.main,
    aws_api_gateway_domain_name.main
  ]
}