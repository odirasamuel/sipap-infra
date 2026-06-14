output "repository_urls" {
  description = "Map of repository names to their URLs"
  value       = local.repository_urls
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value = {
    for repo_name, repo in aws_ecr_repository.app_repositories : repo_name => repo.arn
  }
}

output "repository_registry_ids" {
  description = "Map of repository names to their registry IDs"
  value = {
    for repo_name, repo in aws_ecr_repository.app_repositories : repo_name => repo.registry_id
  }
}

output "repository_names" {
  description = "List of created repository names"
  value       = [for repo in aws_ecr_repository.app_repositories : repo.name]
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}