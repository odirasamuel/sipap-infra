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

# Lambda Function Outputs
output "odds_updater_function_name" {
  description = "Odds updater Lambda function name"
  value       = aws_lambda_function.odds_updater.function_name
}

output "odds_updater_function_arn" {
  description = "Odds updater Lambda function ARN"
  value       = aws_lambda_function.odds_updater.arn
}

output "api_football_odds_updater_function_name" {
  description = "API-Football odds updater Lambda function name"
  value       = aws_lambda_function.api_football_odds_updater.function_name
}

output "api_football_odds_updater_function_arn" {
  description = "API-Football odds updater Lambda function ARN"
  value       = aws_lambda_function.api_football_odds_updater.arn
}

output "fixture_updater_function_name" {
  description = "Fixture updater Lambda function name"
  value       = aws_lambda_function.fixture_updater.function_name
}

output "fixture_updater_function_arn" {
  description = "Fixture updater Lambda function ARN"
  value       = aws_lambda_function.fixture_updater.arn
}

# ECS Task Definition Outputs
output "daily_harvest_task_definition_arn" {
  description = "Daily harvest ECS task definition ARN"
  value       = aws_ecs_task_definition.daily_harvest.arn
}

output "daily_harvest_task_definition_family" {
  description = "Daily harvest ECS task definition family"
  value       = aws_ecs_task_definition.daily_harvest.family
}

# EventBridge Schedule Outputs
output "daily_harvest_schedule_arn" {
  description = "Daily harvest EventBridge schedule ARN"
  value       = aws_cloudwatch_event_rule.daily_harvest.arn
}

output "odds_updater_schedule_arn" {
  description = "Odds updater EventBridge schedule ARN"
  value       = aws_cloudwatch_event_rule.odds_updater.arn
}

output "api_football_odds_updater_schedule_arn" {
  description = "API-Football odds updater EventBridge schedule ARN"
  value       = aws_cloudwatch_event_rule.api_football_odds_updater.arn
}

output "fixture_updater_schedule_arn" {
  description = "Fixture updater EventBridge schedule ARN"
  value       = aws_cloudwatch_event_rule.fixture_updater.arn
}

# CloudWatch Log Group Outputs
output "odds_updater_log_group_name" {
  description = "Odds updater CloudWatch log group name"
  value       = aws_cloudwatch_log_group.odds_updater.name
}

output "api_football_odds_updater_log_group_name" {
  description = "API-Football odds updater CloudWatch log group name"
  value       = aws_cloudwatch_log_group.api_football_odds_updater.name
}

output "fixture_updater_log_group_name" {
  description = "Fixture updater CloudWatch log group name"
  value       = aws_cloudwatch_log_group.fixture_updater.name
}

output "daily_harvest_log_group_name" {
  description = "Daily harvest CloudWatch log group name"
  value       = aws_cloudwatch_log_group.daily_harvest.name
}
