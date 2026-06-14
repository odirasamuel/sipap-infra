# Description: This module creates ECR repositories for container images with lifecycle policies and security configurations
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "app_repositories" {
  for_each = { for repo in var.repositories : repo.name => repo }

  name                 = each.value.name
  image_tag_mutability = each.value.image_tag_mutability

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}"
  }, var.additional_tags)
}

resource "aws_ecr_lifecycle_policy" "app_lifecycle_policy" {
  for_each = { for repo in var.repositories : repo.name => repo if repo.lifecycle_policy != null }

  repository = aws_ecr_repository.app_repositories[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${each.value.lifecycle_policy.keep_last_images} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = each.value.lifecycle_policy.keep_last_images
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${each.value.lifecycle_policy.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.lifecycle_policy.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "app_repository_policy" {
  for_each = { for repo in var.repositories : repo.name => repo if repo.enable_cross_account_access }

  repository = aws_ecr_repository.app_repositories[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "${data.aws_caller_identity.current.account_id}"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
        ]
      }
    ]
  })
}

# ECR Repository URLs for easy reference
locals {
  repository_urls = {
    for repo_name, repo in aws_ecr_repository.app_repositories : repo_name => repo.repository_url
  }
}