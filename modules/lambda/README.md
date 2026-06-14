# Lambda MCP Server Module

This Terraform module creates AWS Lambda functions for MCP (Model Context Protocol) server deployment, supporting both internal and external access patterns. It uses shared layers created by the `lambda_layers` module.

## Features

- **Flexible Deployment**: Choose to create internal, external, or both Lambda functions
- **Source Code Integration**: Automatically archives source directories into ZIP files
- **Shared Layer Support**: Uses layers created by the `lambda_layers` module
- **Configurable Runtime**: Customize runtime, memory, timeout, architecture, and handler
- **API Gateway Integration**: Automatic API Gateway setup for external access (when enabled)
- **VPC Support**: Optional VPC integration for internal functions
- **IAM Security**: Leverages existing IAM roles and policies
- **Auto-deployment**: Changes in source directories trigger automatic redeployment
- **Conditional Resources**: Only creates resources you need based on function type selection

## Resources Created

### Lambda Functions
- **Internal MCP Server**: VPC-enabled function for internal access
- **External MCP Server**: Public function accessible via API Gateway

### API Gateway
- REST API with IAM authorization
- `/mcp` resource endpoint
- Production deployment stage

## Usage

```hcl
# RECOMMENDED: Use shared layers (no conflicts)
module "shared_layers" {
  source = "./modules/lambda_layers"
  
  mcp_handler_source_dir  = "./src/layers/mcp-handler"
  dependencies_source_dir = "./src/layers/dependencies"
}

module "lambda_mcp_server" {
  source = "./modules/lambda"

  internal_function_name     = "internal-mcp-server"
  external_function_name     = "external-mcp-server"
  function_source_dir       = "./src/lambda-functions/mcp-server"
  
  # Required: Layer ARNs from shared layers module
  mcp_handler_layer_arn     = module.shared_layers.mcp_handler_layer_arn
  dependencies_layer_arn    = module.shared_layers.dependencies_layer_arn
  
  lambda_execution_role_arn = module.role.role_arn
  mcp_token_arn            = "arn:aws:secretsmanager:region:account:secret:mcp-token"
  
  # VPC Configuration (optional)
  private_subnet_ids   = ["subnet-12345", "subnet-67890"]
  security_group_ids   = ["sg-abcdef123"]
  
  # Lambda Configuration (optional)
  lambda_runtime      = "python3.12"
  lambda_memory_size  = 256
  lambda_timeout      = 300
  
  additional_tags = {
    Environment = "deltekdev"
    Project     = "sentinel"
  }
}
```