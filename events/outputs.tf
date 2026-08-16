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

# NOTE: batch_scraper_eventbridge_role has been removed
# EventBridge roles are now defined per-task in their respective .tf files
# See: odds_updater_ecs_task.tf for odds updater EventBridge role

# ============================================================================
# NOTE: Lambda function outputs are now in dedicated *_lambda.tf files
# ============================================================================
# Each Lambda .tf file exports:
# - <job>_function_name
# - <job>_function_arn
# - <job>_schedule_rule (if scheduled)

# Note: daily_harvest and fixture_updater removed - replaced by fixture_manager
