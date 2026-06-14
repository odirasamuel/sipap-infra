# VPC Module - Creates VPC with DNS support for SIPAP
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-vpc"
      Environment = var.env
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}
