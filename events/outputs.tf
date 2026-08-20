# ============================================================================
# BATCH SCRAPER EVENTS OUTPUTS
# ============================================================================
# NOTE: Most Lambda/ECS outputs have been removed during API-Football migration.
# Only db_query ECS task remains for database maintenance operations.
# ============================================================================

# DB Query ECS Task (for database maintenance via GitHub Actions)
output "db_query_task_definition_arn" {
  description = "ARN of the db_query ECS task definition"
  value       = aws_ecs_task_definition.db_query.arn
}

output "db_query_task_family" {
  description = "Family name of the db_query ECS task"
  value       = aws_ecs_task_definition.db_query.family
}
