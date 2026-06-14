provider "aws" {
  region = var.aws_region
  profile = "odiraaws"

  default_tags {
    tags = {
      Project     = "SIPAP"
      ManagedBy   = "terraform"
      Environment = var.env
      # Owner       = ""
    }
  }
}
