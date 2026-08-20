# ============================================================================
# BATCH SCRAPER EVENTS INFRASTRUCTURE
# ============================================================================
# NOTE: All scheduled Lambda functions and ECS tasks have been removed.
# The system now uses API-Football directly instead of database-backed caching.
#
# This file is kept for potential future scheduled jobs.
# ============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ============================================================================
# REMOTE STATE DATA SOURCES
# ============================================================================
# Pull values from root terraform state

data "terraform_remote_state" "root" {
  backend = "s3"

  config = {
    bucket  = "sipap-dev-tf-state-bucket"
    key     = "sipap-dev-root-tf-state"
    profile = "odiraaws"
    region  = "us-west-1"
  }
}

# ============================================================================
# NOTE: Lambda/ECS IAM roles and scheduled jobs have been removed
# ============================================================================
# The following resources were removed during the API-Football migration:
# - batch_scraper_lambda_role (Lambda execution role)
# - batch_scraper_ecs_task_role (ECS task role)
# - 9 Lambda functions (fixture_manager, standings_updater, etc.)
# - 6 ECS Fargate tasks (odds_updater, backfill jobs, etc.)
# - backfill_progress DynamoDB table
#
# These can be recreated if scheduled jobs are needed in the future.
# ============================================================================
