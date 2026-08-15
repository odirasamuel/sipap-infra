# ============================================================================
# BATCH SCRAPER EVENTS INFRASTRUCTURE
# ============================================================================
# Deploys 3 scheduled jobs:
# 1. Daily Harvest (Fargate) - daily at 12:00 AM UTC
# 2. API-Football Odds Updater (Lambda) - daily at 10:00 AM UTC (API-Football - 380 competitions)
# 3. Fixture Updater (Lambda) - every 6 hours
#
# All jobs use AWS Secrets Manager for API keys and DB credentials
# Depends on root terraform state for VPC, subnets, security groups, secrets
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
# LOCALS FOR POLICY CHANGE TRACKING
# ============================================================================
# Compute hashes of policy files to detect changes

locals {
  secrets_manager_policy_hash    = filesha256("${path.module}/../modules/policies/secrets_manager_policy.json")
  cloudwatch_logs_policy_hash    = filesha256("${path.module}/../modules/policies/cloudwatch_logs_policy.json")
  lambda_invoke_policy_hash      = filesha256("${path.module}/../modules/policies/lambda_invoke_policy.json")
  ecs_run_task_policy_hash       = filesha256("${path.module}/../modules/policies/ecs_run_task_policy.json")
  dynamodb_backfill_policy_hash  = filesha256("${path.module}/../modules/policies/dynamodb_backfill_policy.json")
}

# ============================================================================
# IAM ROLES
# ============================================================================

# Lambda Execution Role for batch scraper Lambda functions
module "batch_scraper_lambda_role" {
  source = "../modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "batch-scraper-lambda"
  role_description = "Lambda execution role for batch scraper jobs (odds_updater, fixture_updater)"

  assume_role_policy = templatefile("${path.module}/../modules/assume_role_policies/lambda_assume_role.json", {})

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  inline_policies = [
    {
      name = "secrets-manager-access"
      policy = templatefile("${path.module}/../modules/policies/secrets_manager_policy.json", {
        aurora_credentials_secret_arn = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        api_keys_secret_arn           = data.terraform_remote_state.root.outputs.api_keys_secret_arn
      })
    },
    {
      name = "cloudwatch-logs"
      policy = templatefile("${path.module}/../modules/policies/cloudwatch_logs_policy.json", {
        aws_region = data.aws_region.current.name
        account_id = data.aws_caller_identity.current.account_id
        stack_name = var.stack_name
        env        = var.env
      })
    },
    {
      name = "dynamodb-backfill-progress"
      policy = templatefile("${path.module}/../modules/policies/dynamodb_backfill_policy.json", {
        aws_region = data.aws_region.current.name
        account_id = data.aws_caller_identity.current.account_id
        stack_name = var.stack_name
        env        = var.env
      })
    }
  ]

  additional_tags = merge(var.additional_tags, {
    SecretsManagerPolicyHash = local.secrets_manager_policy_hash
    CloudWatchLogsPolicyHash = local.cloudwatch_logs_policy_hash
    DynamoDBPolicyHash       = local.dynamodb_backfill_policy_hash
  })
}

# ECS Task Role for daily harvest Fargate task
module "batch_scraper_ecs_task_role" {
  source = "../modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "batch-scraper-ecs-task"
  role_description = "ECS task role for batch scraper daily harvest job"

  assume_role_policy = templatefile("${path.module}/../modules/assume_role_policies/ecs_task_assume_role.json", {})

  inline_policies = [
    {
      name = "secrets-manager-access"
      policy = templatefile("${path.module}/../modules/policies/secrets_manager_policy.json", {
        aurora_credentials_secret_arn = data.terraform_remote_state.root.outputs.aurora_credentials_secret_arn
        api_keys_secret_arn           = data.terraform_remote_state.root.outputs.api_keys_secret_arn
      })
    }
  ]

  additional_tags = merge(var.additional_tags, {
    SecretsManagerPolicyHash = local.secrets_manager_policy_hash
  })
}

# EventBridge Role for invoking Lambda and ECS tasks
module "batch_scraper_eventbridge_role" {
  source = "../modules/role"

  stack_name       = var.stack_name
  env              = var.env
  aws_region       = var.aws_region
  stack_tool       = "batch-scraper-eventbridge"
  role_description = "EventBridge role for invoking batch scraper Lambda and ECS tasks"

  assume_role_policy = templatefile("${path.module}/../modules/assume_role_policies/eventbridge_assume_role.json", {})

  inline_policies = [
    {
      name = "invoke-lambda"
      policy = templatefile("${path.module}/../modules/policies/lambda_invoke_policy.json", {
        api_football_odds_updater_function_arn  = aws_lambda_function.api_football_odds_updater.arn
        # fixture_updater removed - replaced by fixture_manager
      })
    }
  ]

  additional_tags = merge(var.additional_tags, {
    LambdaInvokePolicyHash = local.lambda_invoke_policy_hash
    EcsRunTaskPolicyHash   = local.ecs_run_task_policy_hash
  })
}

# ============================================================================
# NOTE: Lambda functions are now defined in dedicated *_lambda.tf files
# ============================================================================
# - daily_harvest_lambda.tf
# - standings_updater_lambda.tf
# - team_stats_updater_lambda.tf
# - teams_metadata_sync_lambda.tf
# - injuries_updater_lambda.tf
# - lineups_fetcher_lambda.tf
# - api_football_odds_updater_lambda.tf
# - fixture_updater_lambda.tf
# - h2h_fetcher_lambda.tf
# - db_query_lambda.tf
# - integration_test_lambda.tf

# ============================================================================
# NOTE: EventBridge schedules and Lambda resources are defined in their
# respective files (e.g., api_football_odds_updater_lambda.tf)
# ============================================================================
