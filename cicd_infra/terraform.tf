terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.91"
    }
  }

  backend "s3" {
    bucket         = "sipap-dev-tf-state-bucket"
    dynamodb_table = "sipap-dev-tf-state-lock"
    key            = "sipap-dev-cicd-infra-tf-state"
    encrypt        = true
    profile        = "odiraaws"
    region         = "us-west-1"
  }
}
