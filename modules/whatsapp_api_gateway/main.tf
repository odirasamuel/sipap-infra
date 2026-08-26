# WhatsApp API Gateway Module
# REST API Gateway with direct SQS integration for WhatsApp webhook processing

# Data sources
data "aws_region" "current" {}

# ==============================================================================
# REST API Gateway
# ==============================================================================

resource "aws_api_gateway_rest_api" "whatsapp" {
  name        = "${var.stack_name}-${var.env}-whatsapp-webhook"
  description = "WhatsApp webhook → SQS integration for SIPAP (asynchronous message processing)"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-webhook"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# API Gateway Resources and Methods
# ==============================================================================

# /webhook resource
resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.whatsapp.id
  parent_id   = aws_api_gateway_rest_api.whatsapp.root_resource_id
  path_part   = "webhook"
}

# POST /webhook method
resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id      = aws_api_gateway_rest_api.whatsapp.id
  resource_id      = aws_api_gateway_resource.webhook.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = false  # Twilio cannot send custom headers; rely on X-Twilio-Signature validation instead
}

# ==============================================================================
# SQS Integration (used when use_lambda_integration = false)
# ==============================================================================

# Direct AWS service integration with SQS using VTL
resource "aws_api_gateway_integration" "sqs" {
  count = var.use_lambda_integration ? 0 : 1

  rest_api_id = aws_api_gateway_rest_api.whatsapp.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:action/SendMessage"
  credentials             = aws_iam_role.api_gateway_sqs.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # VTL template: Transform Twilio webhook → SQS SendMessage params
  # MessageGroupId = phone number from From field (extracted from form data, already URL-encoded)
  # MessageDeduplicationId = request ID (prevents duplicates)
  # MessageBody = raw Twilio form data (orchestrator will parse it)
  request_templates = {
    "application/json" = "Action=SendMessage&QueueUrl=${var.sqs_queue_url}&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$util.urlEncode($input.path('$.From'))&MessageDeduplicationId=$context.requestId"
    "application/x-www-form-urlencoded" = "#set($formData = $input.body.split(\"&\"))#set($fromValue = \"\")#set($bodyValue = \"\")#foreach($param in $formData)#if($param.startsWith(\"From=\"))#set($fromValue = $param.substring(5))#end#if($param.startsWith(\"Body=\"))#set($bodyValue = $param.substring(5))#end#end##\nAction=SendMessage&QueueUrl=${var.sqs_queue_url}&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$fromValue&MessageDeduplicationId=$context.requestId"
  }

  timeout_milliseconds = 29000
}

# ==============================================================================
# Lambda Proxy Integration (used when use_lambda_integration = true)
# ==============================================================================

# Lambda proxy integration for auth handler
resource "aws_api_gateway_integration" "lambda" {
  count = var.use_lambda_integration ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.whatsapp.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn

  timeout_milliseconds = 29000
}

# Lambda permission for API Gateway to invoke
resource "aws_lambda_permission" "api_gateway" {
  count = var.use_lambda_integration ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke-${var.stack_name}-${var.env}"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.whatsapp.execution_arn}/*/*"
}

# Method response (for SQS integration)
resource "aws_api_gateway_method_response" "webhook_200" {
  count = var.use_lambda_integration ? 0 : 1

  rest_api_id = aws_api_gateway_rest_api.whatsapp.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Type" = true
  }

  # Twilio expects TwiML (XML) response format
  response_models = {
    "text/xml" = "Empty"
  }
}

# Integration response (for SQS integration)
resource "aws_api_gateway_integration_response" "webhook_200" {
  count = var.use_lambda_integration ? 0 : 1

  rest_api_id = aws_api_gateway_rest_api.whatsapp.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method
  status_code = aws_api_gateway_method_response.webhook_200[0].status_code

  response_parameters = {
    "method.response.header.Content-Type" = "'text/xml'"
  }

  # Return TwiML (XML) response - Twilio requires XML format to avoid Error 12300
  # Multiple templates to handle different SQS response content-types
  response_templates = {
    "application/json"              = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
    "application/x-www-form-urlencoded" = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
    "text/xml"                      = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
    "application/xml"               = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
    "application/x-amz-json-1.0"    = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>"
  }

  # Convert binary/non-text responses to text to ensure proper template application
  content_handling = "CONVERT_TO_TEXT"

  depends_on = [aws_api_gateway_integration.sqs]
}

# ==============================================================================
# Deployment and Stage
# ==============================================================================

resource "aws_api_gateway_deployment" "whatsapp" {
  rest_api_id = aws_api_gateway_rest_api.whatsapp.id

  # Trigger new deployment when method or integration configuration changes
  # Use full resource content, not just IDs, to detect config changes
  # Also include any additional triggers from external routes (e.g., payment routes)
  triggers = merge(
    {
      redeployment = sha1(jsonencode({
        method      = aws_api_gateway_method.webhook_post
        integration = var.use_lambda_integration ? aws_api_gateway_integration.lambda[0].id : aws_api_gateway_integration.sqs[0].id
        response    = var.use_lambda_integration ? "lambda-proxy" : aws_api_gateway_integration_response.webhook_200[0].id
      }))
    },
    var.additional_deployment_triggers
  )

  # Add description with hash to ensure deployment is actually created
  description = var.use_lambda_integration ? "Lambda proxy integration deployment" : "Deployment triggered by config hash: ${sha1(jsonencode([
    aws_api_gateway_integration_response.webhook_200[0].response_parameters,
    aws_api_gateway_integration_response.webhook_200[0].response_templates
  ]))}"

  depends_on = [
    aws_api_gateway_integration.sqs,
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration_response.webhook_200,
    aws_api_gateway_method_response.webhook_200
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.whatsapp.id
  rest_api_id   = aws_api_gateway_rest_api.whatsapp.id
  stage_name    = "prod"

  xray_tracing_enabled = var.enable_xray_tracing

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-webhook-prod"
      Environment = var.env
      Stage       = "prod"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )

  # Allow external deployments (like payment routes in core_deploy) to update
  # this stage without Terraform trying to revert to the module's deployment
  lifecycle {
    ignore_changes = [deployment_id]
  }
}

# ==============================================================================
# CloudWatch Logging
# ==============================================================================

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.stack_name}-${var.env}-whatsapp-webhook"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-api-gateway-logs"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# API Key and Usage Plan
# ==============================================================================

resource "aws_api_gateway_api_key" "twilio" {
  name = "${var.stack_name}-${var.env}-twilio-webhook-key"

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-twilio-webhook-key"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Purpose     = "twilio-authentication"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

resource "aws_api_gateway_usage_plan" "whatsapp" {
  name = "${var.stack_name}-${var.env}-whatsapp-usage-plan"

  # api_stages removed - Twilio cannot send API keys in custom headers
  # Usage plan preserved for potential future use with Twilio signature validation
  # api_stages {
  #   api_id = aws_api_gateway_rest_api.whatsapp.id
  #   stage  = aws_api_gateway_stage.prod.stage_name
  # }

  throttle_settings {
    rate_limit  = var.throttle_rate_limit
    burst_limit = var.throttle_burst_limit
  }

  quota_settings {
    limit  = var.quota_limit
    period = var.quota_period
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-whatsapp-usage-plan"
      Environment = var.env
      Service     = "whatsapp-webhook"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

resource "aws_api_gateway_usage_plan_key" "twilio" {
  key_id        = aws_api_gateway_api_key.twilio.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.whatsapp.id
}

# ==============================================================================
# IAM Role for API Gateway → SQS Integration
# ==============================================================================

resource "aws_iam_role" "api_gateway_sqs" {
  name = "${var.stack_name}-${var.env}-api-gateway-sqs-role"

  assume_role_policy = templatefile("${path.module}/../assume_role_policies/apigateway_assume_role.json", {})

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-api-gateway-sqs-role"
      Environment = var.env
      Service     = "api-gateway"
      Purpose     = "sqs-integration"
      Project     = "SIPAP"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

resource "aws_iam_role_policy" "api_gateway_sqs" {
  role = aws_iam_role.api_gateway_sqs.id

  policy = templatefile("${path.module}/../policies/sqs_send_policy.json", {
    queue_arn = var.sqs_queue_arn
  })
}
