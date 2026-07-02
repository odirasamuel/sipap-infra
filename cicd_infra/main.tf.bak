data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# resource "aws_s3_bucket" "lambda_packages" {
#   bucket = "${var.stack_name}-lambda-packages-${var.env}"

#   tags = merge(
#     {
#       Name        = "${var.stack_name}-lambda-packages-${var.env}"
#       Purpose     = "Store versioned Lambda deployment packages"
#       Environment = var.env
#     },
#     var.additional_tags
#   )
# }

# # Enable versioning for rollback capability
# resource "aws_s3_bucket_versioning" "lambda_packages" {
#   bucket = aws_s3_bucket.lambda_packages.id

#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# # Enable server-side encryption
# resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_packages" {
#   bucket = aws_s3_bucket.lambda_packages.id

#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# # Block all public access
# resource "aws_s3_bucket_public_access_block" "lambda_packages" {
#   bucket = aws_s3_bucket.lambda_packages.id

#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

# # Lifecycle policy for old versions
# resource "aws_s3_bucket_lifecycle_configuration" "lambda_packages" {
#   bucket = aws_s3_bucket.lambda_packages.id

#   rule {
#     id     = "cleanup-old-versions"
#     status = "Enabled"

#     # Apply to all objects in the bucket
#     filter {}

#     noncurrent_version_expiration {
#       noncurrent_days = var.lifecycle_noncurrent_days
#     }

#     abort_incomplete_multipart_upload {
#       days_after_initiation = 7
#     }
#   }
# }


# GITHUB ACTIONS OIDC CONFIGURATION
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = "${var.stack_name}-${var.env}-github-actions-role"
  description        = "IAM role for GitHub Actions OIDC authentication (supports all sipap-* repos)"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-github-actions-role"
      Description = "GitHub Actions Deployment Role"
      Environment = var.env
    },
    var.additional_tags
  )
}

# Assume role policy for GitHub Actions OIDC
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Wildcard pattern supports all sipap-* repos in the org
      values = [
        "repo:${var.github_org}/sipap*"
        # "repo:${var.github_org}/sre-sipap*"
      ]
    }
  }
}

# # IAM Policy for S3 and Lambda operations
# data "aws_iam_policy_document" "github_actions_permissions" {
#   # S3 permissions for Lambda packages bucket
#   statement {
#     sid = "S3LambdaPackagesAccess"

#     actions = [
#       "s3:PutObject",
#       "s3:GetObject",
#       "s3:DeleteObject",
#       "s3:ListBucket",
#       "s3:GetObjectVersion",
#       "s3:ListBucketVersions"
#     ]

#     resources = [
#       aws_s3_bucket.lambda_packages.arn,
#       "${aws_s3_bucket.lambda_packages.arn}/*"
#     ]
#   }
# }

# Compute hashes of policy files to detect changes
locals {
  # deploy_policy_1_hash = filesha256("${path.module}/../modules/policies/deploy_policy_1.json")
  # deploy_policy_2_hash = filesha256("${path.module}/../modules/policies/deploy_policy_2.json")
  # deploy_policy_3_hash = filesha256("${path.module}/../modules/policies/deploy_policy_3.json")
  # deploy_policy_4_hash = filesha256("${path.module}/../modules/policies/deploy_policy_4.json")
  deploy_policy_5_hash = filesha256("${path.module}/../modules/policies/deploy_policy_5.json")
}

# Create customer-managed policies and attach to the role
# # S3 Lambda packages policy
# resource "aws_iam_policy" "github_actions_s3" {
#   name        = "${var.stack_name}-${var.env}-github-actions-s3-policy"
#   description = "S3 permissions for Lambda packages bucket"
#   policy      = data.aws_iam_policy_document.github_actions_permissions.json
# }

# # Deployment policy 1
# resource "aws_iam_policy" "github_actions_deploy_1" {
#   name        = "${var.stack_name}-${var.env}-github-actions-deploy-policy-1"
#   description = "Deployment permissions set 1"
#   policy = templatefile("${path.module}/../modules/policies/deploy_policy_1.json", {
#     account_id = data.aws_caller_identity.current.account_id
#   })

#   tags = merge(
#     var.additional_tags,
#     {
#       PolicyHash = local.deploy_policy_1_hash
#     }
#   )
# }

# # Deployment policy 2
# resource "aws_iam_policy" "github_actions_deploy_2" {
#   name        = "${var.stack_name}-${var.env}-github-actions-deploy-policy-2"
#   description = "Deployment permissions set 2"
#   policy      = file("${path.module}/../modules/policies/deploy_policy_2.json")

#   tags = merge(
#     var.additional_tags,
#     {
#       PolicyHash = local.deploy_policy_2_hash
#     }
#   )
# }

# # Deployment policy 3
# resource "aws_iam_policy" "github_actions_deploy_3" {
#   name        = "${var.stack_name}-${var.env}-github-actions-deploy-policy-3"
#   description = "Deployment permissions set 3"
#   policy      = file("${path.module}/../modules/policies/deploy_policy_3.json")

#   tags = merge(
#     var.additional_tags,
#     {
#       PolicyHash = local.deploy_policy_3_hash
#     }
#   )
# }

# # Deployment policy 4
# resource "aws_iam_policy" "github_actions_deploy_4" {
#   name        = "${var.stack_name}-${var.env}-github-actions-deploy-policy-4"
#   description = "Deployment permissions set 4"
#   policy      = file("${path.module}/../modules/policies/deploy_policy_4.json")

#   tags = merge(
#     var.additional_tags,
#     {
#       PolicyHash = local.deploy_policy_4_hash
#     }
#   )
# }

# Deployment policy 5
resource "aws_iam_policy" "github_actions_deploy_5" {
  name        = "${var.stack_name}-${var.env}-github-actions-deploy-policy-5"
  description = "Deployment permissions set 5"
  policy      = file("${path.module}/../modules/policies/deploy_policy_5.json")

  tags = merge(
    var.additional_tags,
    {
      PolicyHash = local.deploy_policy_5_hash
    }
  )
}

# Attach all policies to the GitHub Actions role
# resource "aws_iam_role_policy_attachment" "github_actions_s3" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = aws_iam_policy.github_actions_s3.arn
# }

# resource "aws_iam_role_policy_attachment" "github_actions_deploy_1" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = aws_iam_policy.github_actions_deploy_1.arn
# }

# resource "aws_iam_role_policy_attachment" "github_actions_deploy_2" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = aws_iam_policy.github_actions_deploy_2.arn
# }

# resource "aws_iam_role_policy_attachment" "github_actions_deploy_3" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = aws_iam_policy.github_actions_deploy_3.arn
# }

# resource "aws_iam_role_policy_attachment" "github_actions_deploy_4" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = aws_iam_policy.github_actions_deploy_4.arn
# }

resource "aws_iam_role_policy_attachment" "github_actions_deploy_5" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy_5.arn
}
