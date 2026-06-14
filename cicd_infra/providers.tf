provider "aws" {
  region  = var.aws_region
  profile = "odiraaws"

  default_tags {
    tags = {
      Environment = var.env
      ManagedBy   = "Terraform"
      Project     = "SIPAP"
      Component   = "CICD-Infrastructure"
    }
  }
}