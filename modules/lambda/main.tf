data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Validation: Ensure required variables are provided based on deployment method
locals {
  validate_local_deployment = (
    !var.use_s3_deployment && var.function_source_dir == null
    ? tobool("ERROR: function_source_dir is required when use_s3_deployment is false")
    : true
  )

  validate_s3_deployment = (
    var.use_s3_deployment && (var.s3_bucket == null || var.s3_key == null)
    ? tobool("ERROR: s3_bucket and s3_key are required when use_s3_deployment is true")
    : true
  )
}

# Archive Lambda function from source directory (only for local deployment)
data "archive_file" "function_code" {
  count = var.use_s3_deployment ? 0 : 1

  type        = "zip"
  source_dir  = var.function_source_dir
  output_path = "../../deltekdev_infra_ecs/core_deploy/zipped/${var.internal_function_name}.zip"
}

resource "aws_lambda_function" "internal_mcp_server" {
  count = var.create_internal_function ? 1 : 0

  function_name = var.internal_function_name
  description   = var.internal_lambda_description
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  handler       = var.lambda_handler
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Conditional deployment source - use S3 or local archive
  filename         = var.use_s3_deployment ? null : data.archive_file.function_code[0].output_path
  source_code_hash = var.use_s3_deployment ? null : data.archive_file.function_code[0].output_base64sha256

  s3_bucket         = var.use_s3_deployment ? var.s3_bucket : null
  s3_key            = var.use_s3_deployment ? var.s3_key : null
  s3_object_version = var.use_s3_deployment ? var.s3_object_version : null

  role = var.lambda_execution_role_arn

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = var.security_group_ids
  }

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_size
  }

  layers = concat([
    var.mcp_handler_layer_arn,
    var.dependencies_layer_arn,
    "arn:aws:lambda:${data.aws_region.current.name}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:20"
  ], var.additional_internal_layer_arns)

  environment {
    variables = merge({
      MCP_TOKEN_ARN = var.mcp_token_arn
    }, var.internal_lambda_environment_variables)
  }

  tags = merge({
    Name             = var.internal_function_name
    Owner            = "sentinel-automation"
    DeploymentMethod = var.use_s3_deployment ? "S3" : "Local"
  }, var.additional_tags)
}

resource "aws_lambda_function" "external_mcp_server" {
  count = var.create_external_function ? 1 : 0

  function_name = var.external_function_name
  description   = var.external_lambda_description
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  handler       = var.lambda_handler
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Conditional deployment source - use S3 or local archive
  filename         = var.use_s3_deployment ? null : data.archive_file.function_code[0].output_path
  source_code_hash = var.use_s3_deployment ? null : data.archive_file.function_code[0].output_base64sha256

  s3_bucket         = var.use_s3_deployment ? var.s3_bucket : null
  s3_key            = var.use_s3_deployment ? var.s3_key : null
  s3_object_version = var.use_s3_deployment ? var.s3_object_version : null

  role = var.lambda_execution_role_arn

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_size
  }

  layers = concat([
    var.mcp_handler_layer_arn,
    var.dependencies_layer_arn,
    "arn:aws:lambda:${data.aws_region.current.name}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:20"
  ], var.additional_external_layer_arns)

  environment {
    variables = merge({
      MCP_TOKEN_ARN = var.mcp_token_arn
    }, var.external_lambda_environment_variables)
  }

  tags = merge({
    Name             = var.external_function_name
    Owner            = "sentinel-automation"
    DeploymentMethod = var.use_s3_deployment ? "S3" : "Local"
  }, var.additional_tags)
}

resource "aws_lambda_function_url" "internal_function_url" {
  count = var.create_internal_function && var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.internal_mcp_server[0].function_name
  authorization_type = var.function_url_auth_type

  cors {
    allow_credentials = var.function_url_cors.allow_credentials
    allow_origins     = var.function_url_cors.allow_origins
    allow_methods     = var.function_url_cors.allow_methods
    allow_headers     = var.function_url_cors.allow_headers
    expose_headers    = var.function_url_cors.expose_headers
    max_age           = var.function_url_cors.max_age
  }
}

resource "aws_lambda_function_url" "external_function_url" {
  count = var.create_external_function && var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.external_mcp_server[0].function_name
  authorization_type = var.function_url_auth_type

  cors {
    allow_credentials = var.function_url_cors.allow_credentials
    allow_origins     = var.function_url_cors.allow_origins
    allow_methods     = var.function_url_cors.allow_methods
    allow_headers     = var.function_url_cors.allow_headers
    expose_headers    = var.function_url_cors.expose_headers
    max_age           = var.function_url_cors.max_age
  }
}

# Allow orchestrator task role to invoke internal Lambda function
resource "aws_lambda_permission" "allow_orchestrator_internal_invoke" {
  count = var.create_internal_function && var.enable_orchestrator_invoke_permissions ? 1 : 0

  statement_id           = "AllowOrchestratorInvoke"
  action                 = "lambda:InvokeFunction"
  function_name          = aws_lambda_function.internal_mcp_server[0].function_name
  principal              = "sts.amazonaws.com"
  source_account         = data.aws_caller_identity.current.account_id
  principal_org_id       = null
  source_arn             = var.orchestrator_task_role_arn
  function_url_auth_type = null
}

# Allow orchestrator task role to invoke internal Lambda Function URL
resource "aws_lambda_permission" "allow_orchestrator_internal_url_invoke" {
  count = var.create_internal_function && var.enable_function_url && var.enable_orchestrator_invoke_permissions ? 1 : 0

  statement_id           = "AllowOrchestratorFunctionURLInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.internal_mcp_server[0].function_name
  principal              = "sts.amazonaws.com"
  source_account         = data.aws_caller_identity.current.account_id
  principal_org_id       = null
  source_arn             = var.orchestrator_task_role_arn
  function_url_auth_type = "AWS_IAM"
}

# Allow orchestrator task role to invoke external Lambda function
resource "aws_lambda_permission" "allow_orchestrator_external_invoke" {
  count = var.create_external_function && var.enable_orchestrator_invoke_permissions ? 1 : 0

  statement_id           = "AllowOrchestratorInvoke"
  action                 = "lambda:InvokeFunction"
  function_name          = aws_lambda_function.external_mcp_server[0].function_name
  principal              = "sts.amazonaws.com"
  source_account         = data.aws_caller_identity.current.account_id
  principal_org_id       = null
  source_arn             = var.orchestrator_task_role_arn
  function_url_auth_type = null
}

# Allow orchestrator task role to invoke external Lambda Function URL
resource "aws_lambda_permission" "allow_orchestrator_external_url_invoke" {
  count = var.create_external_function && var.enable_function_url && var.enable_orchestrator_invoke_permissions ? 1 : 0

  statement_id           = "AllowOrchestratorFunctionURLInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.external_mcp_server[0].function_name
  principal              = "sts.amazonaws.com"
  source_account         = data.aws_caller_identity.current.account_id
  principal_org_id       = null
  source_arn             = var.orchestrator_task_role_arn
  function_url_auth_type = "AWS_IAM"
}

# SSM Parameter for Internal Lambda Function URL
resource "aws_ssm_parameter" "internal_function_url" {
  count = var.create_internal_function && var.enable_function_url && var.create_ssm_parameter && var.ssm_service_identifier != "" ? 1 : 0

  name        = var.ssm_parameter_name_override != "" ? var.ssm_parameter_name_override : "/sre/sentinel-mcp-${var.ssm_service_identifier}"
  description = "MCP Lambda Function URL configuration for ${var.internal_function_name}"
  type        = "String"
  tier        = "Standard"

  value = jsonencode({
    "${upper(var.ssm_service_identifier)}_MCP_URL"     = "${aws_lambda_function_url.internal_function_url[0].function_url}mcp"
    "${upper(var.ssm_service_identifier)}_MCP_TIMEOUT" = var.ssm_mcp_timeout
  })

  tags = merge({
    Name         = "/sre/sentinel-mcp-${var.ssm_service_identifier}"
    ManagedBy    = "terraform"
    Service      = "lambda"
    FunctionName = var.internal_function_name
  }, var.additional_tags)
}

# SSM Parameter for External Lambda Function URL
resource "aws_ssm_parameter" "external_function_url" {
  count = var.create_external_function && var.enable_function_url && var.create_ssm_parameter_external && var.ssm_service_identifier_external != "" ? 1 : 0

  name        = var.ssm_parameter_name_override_external != "" ? var.ssm_parameter_name_override_external : "/sre/sentinel-mcp-${var.ssm_service_identifier_external}"
  description = "MCP Lambda Function URL configuration for ${var.external_function_name}"
  type        = "String"
  tier        = "Standard"

  value = jsonencode({
    "${upper(var.ssm_service_identifier_external)}_MCP_URL"     = "${aws_lambda_function_url.external_function_url[0].function_url}mcp"
    "${upper(var.ssm_service_identifier_external)}_MCP_TIMEOUT" = var.ssm_mcp_timeout
  })

  tags = merge({
    Name         = "/sre/sentinel-mcp-${var.ssm_service_identifier_external}"
    ManagedBy    = "terraform"
    Service      = "lambda"
    FunctionName = var.external_function_name
  }, var.additional_tags)
}