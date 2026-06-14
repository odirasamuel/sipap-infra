terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { version = "~> 5.91" }
  }

  backend "s3" {
    bucket         = "sipap-dev-tf-state-bucket"
    dynamodb_table = "sipap-dev-tf-state-lock"
    key            = "sipap-dev-backend-tf-state"
    encrypt        = true
    profile        = "odiraaws"
    region         = "us-west-1"
  }
  # backend "s3" {
  #   # Backend configuration supplied via -backend-config during terraform init
  # }
}