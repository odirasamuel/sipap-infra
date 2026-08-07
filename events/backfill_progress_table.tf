# ============================================================================
# HISTORICAL BACKFILL PROGRESS TRACKING TABLE
# ============================================================================
# DynamoDB table to track progress of historical data backfill jobs
# Used by historical_backfill_orchestrator.py to enable resume capability

resource "aws_dynamodb_table" "backfill_progress" {
  name           = "${var.stack_name}-${var.env}-backfill-progress"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "backfill_id"
  range_key      = "job_type"

  attribute {
    name = "backfill_id"
    type = "S" # Format: "2025-standings", "2024-fixtures", "2023-team-stats", etc.
  }

  attribute {
    name = "job_type"
    type = "S" # "standings", "fixtures", "team_stats", "all"
  }

  attribute {
    name = "status"
    type = "S" # "pending", "in_progress", "completed", "failed"
  }

  # Global Secondary Index for querying by status
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    projection_type = "ALL"
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-backfill-progress"
      Environment = var.env
      ManagedBy   = "Terraform"
      Purpose     = "historical-data-backfill-tracking"
    },
    var.additional_tags
  )
}

# Output the table name for use by backfill jobs
output "backfill_progress_table_name" {
  description = "DynamoDB table name for backfill progress tracking"
  value       = aws_dynamodb_table.backfill_progress.name
}

output "backfill_progress_table_arn" {
  description = "ARN of backfill progress tracking table"
  value       = aws_dynamodb_table.backfill_progress.arn
}
