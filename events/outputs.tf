# ============================================================================
# BATCH SCRAPER EVENTS OUTPUTS
# ============================================================================

# IAM Role Outputs
output "batch_scraper_lambda_role_arn" {
  description = "ARN of batch scraper Lambda execution role"
  value       = module.batch_scraper_lambda_role.role_arn
}

output "batch_scraper_ecs_task_role_arn" {
  description = "ARN of batch scraper ECS task role"
  value       = module.batch_scraper_ecs_task_role.role_arn
}

output "batch_scraper_eventbridge_role_arn" {
  description = "ARN of batch scraper EventBridge role"
  value       = module.batch_scraper_eventbridge_role.role_arn
}

# ============================================================================
# NOTE: Lambda function outputs are now in dedicated *_lambda.tf files
# ============================================================================
# Each Lambda .tf file exports:
# - <job>_function_name
# - <job>_function_arn
# - <job>_schedule_rule (if scheduled)

# Note: daily_harvest and fixture_updater removed - replaced by fixture_manager
