# output "lambda_packages_bucket_name" {
#   description = "Name of the S3 bucket for Lambda packages"
#   value       = aws_s3_bucket.lambda_packages.id
# }

# output "lambda_packages_bucket_arn" {
#   description = "ARN of the S3 bucket for Lambda packages"
#   value       = aws_s3_bucket.lambda_packages.arn
# }

# output "lambda_packages_bucket_region" {
#   description = "AWS region where the Lambda packages bucket is located"
#   value       = aws_s3_bucket.lambda_packages.region
# }

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions (use this in GitHub secrets)"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (existing provider)"
  value       = data.aws_iam_openid_connect_provider.github_actions.arn
}

output "github_org_pattern" {
  description = "GitHub organization pattern allowed by OIDC (shows which repos can assume the role)"
  value       = "${var.github_org}/sipap-*"
}
