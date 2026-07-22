# Lambda Layers Module for SIPAP
# Supports S3-based deployment (production) and local deployment (development)

# ==============================================================================
# VALIDATION LOGIC
# ==============================================================================

locals {
  # Validate local deployment requirements
  validate_mcp_handler_local = (
    !var.use_s3_deployment && var.create_mcp_handler_layer && var.mcp_handler_source_dir == null
    ? tobool("ERROR: mcp_handler_source_dir is required when use_s3_deployment is false and create_mcp_handler_layer is true")
    : true
  )

  validate_dependencies_local = (
    !var.use_s3_deployment && var.create_dependencies_layer && var.dependencies_source_dir == null
    ? tobool("ERROR: dependencies_source_dir is required when use_s3_deployment is false and create_dependencies_layer is true")
    : true
  )

  # Validate S3 deployment requirements
  validate_mcp_handler_s3 = (
    var.use_s3_deployment && var.create_mcp_handler_layer && (var.s3_bucket == null || var.mcp_handler_s3_key == null)
    ? tobool("ERROR: s3_bucket and mcp_handler_s3_key are required when use_s3_deployment is true and create_mcp_handler_layer is true")
    : true
  )

  validate_dependencies_s3 = (
    var.use_s3_deployment && var.create_dependencies_layer && (var.s3_bucket == null || var.dependencies_s3_key == null)
    ? tobool("ERROR: s3_bucket and dependencies_s3_key are required when use_s3_deployment is true and create_dependencies_layer is true")
    : true
  )
}

# ==============================================================================
# MCP HANDLER LAYER
# ==============================================================================

# Data source to detect S3 object changes for MCP handler layer
data "aws_s3_object" "mcp_handler_layer" {
  count = (var.use_s3_deployment && var.create_mcp_handler_layer) ? 1 : 0

  bucket = var.s3_bucket
  key    = var.mcp_handler_s3_key
}

# Archive MCP handler layer from source directory (only for local deployment)
data "archive_file" "mcp_handler_layer" {
  count = (!var.use_s3_deployment && var.create_mcp_handler_layer) ? 1 : 0

  type        = "zip"
  source_dir  = var.mcp_handler_source_dir
  output_path = "${path.root}/zipped/${var.mcp_handler_layer_name}.zip"
}

resource "aws_lambda_layer_version" "sipap_serverless_mcp_handler" {
  count = var.create_mcp_handler_layer ? 1 : 0

  layer_name  = var.mcp_handler_layer_name
  description = var.mcp_handler_description

  # Conditional deployment source - use S3 or local archive
  filename         = var.use_s3_deployment ? null : data.archive_file.mcp_handler_layer[0].output_path
  source_code_hash = var.use_s3_deployment ? data.aws_s3_object.mcp_handler_layer[0].etag : data.archive_file.mcp_handler_layer[0].output_base64sha256

  s3_bucket         = var.use_s3_deployment ? var.s3_bucket : null
  s3_key            = var.use_s3_deployment ? var.mcp_handler_s3_key : null
  s3_object_version = var.use_s3_deployment ? var.mcp_handler_s3_version : null

  compatible_runtimes      = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures

  # Note: aws_lambda_layer_version does not support tags in AWS provider 5.x
}

# ==============================================================================
# DEPENDENCIES LAYER
# ==============================================================================

# Data source to detect S3 object changes for dependencies layer
data "aws_s3_object" "dependencies_layer" {
  count = (var.use_s3_deployment && var.create_dependencies_layer) ? 1 : 0

  bucket = var.s3_bucket
  key    = var.dependencies_s3_key
}

# Archive dependencies layer from source directory (only for local deployment)
data "archive_file" "dependencies_layer" {
  count = (!var.use_s3_deployment && var.create_dependencies_layer) ? 1 : 0

  type        = "zip"
  source_dir  = var.dependencies_source_dir
  output_path = "${path.root}/zipped/${var.dependencies_layer_name}.zip"
}

resource "aws_lambda_layer_version" "sipap_dependencies" {
  count = var.create_dependencies_layer ? 1 : 0

  layer_name  = var.dependencies_layer_name
  description = var.dependencies_description

  # Conditional deployment source - use S3 or local archive
  filename         = var.use_s3_deployment ? null : data.archive_file.dependencies_layer[0].output_path
  source_code_hash = var.use_s3_deployment ? data.aws_s3_object.dependencies_layer[0].etag : data.archive_file.dependencies_layer[0].output_base64sha256

  s3_bucket         = var.use_s3_deployment ? var.s3_bucket : null
  s3_key            = var.use_s3_deployment ? var.dependencies_s3_key : null
  s3_object_version = var.use_s3_deployment ? var.dependencies_s3_version : null

  compatible_runtimes      = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures

  # Note: aws_lambda_layer_version does not support tags in AWS provider 5.x
}
