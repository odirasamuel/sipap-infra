# Provider configuration for core_deploy (separate root module)

provider "aws" {
  region  = var.aws_region
  profile = "odiraaws"

  default_tags {
    tags = {
      Project     = "SIPAP"
      Environment = var.env
      ManagedBy   = "Terraform"
      Module      = "core_deploy"
    }
  }
}
