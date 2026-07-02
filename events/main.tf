# ============================================================================
# BATCH SCRAPER EVENTS INFRASTRUCTURE
# ============================================================================
# Deploys 3 scheduled jobs:
# 1. Daily Harvest (Fargate) - daily at 12:00 AM UTC
# 2. Odds Updater (Lambda) - daily at 9:00 AM UTC
# 3. Fixture Updater (Lambda) - hourly
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
# S3 OBJECT DATA SOURCES FOR LAMBDA PACKAGES
# ============================================================================
# These data sources track S3 object changes to trigger Lambda updates

data "aws_s3_object" "odds_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/odds_updater.zip"
}

data "aws_s3_object" "fixture_updater" {
  bucket = var.lambda_s3_bucket
  key    = "${var.lambda_s3_key_prefix}/fixture_updater.zip"
}

# ============================================================================
# LOCALS FOR POLICY CHANGE TRACKING
# ============================================================================
# Compute hashes of policy files to detect changes

locals {
  secrets_manager_policy_hash = filesha256("${path.module}/../modules/policies/secrets_manager_policy.json")
  cloudwatch_logs_policy_hash = filesha256("${path.module}/../modules/policies/cloudwatch_logs_policy.json")
  lambda_invoke_policy_hash   = filesha256("${path.module}/../modules/policies/lambda_invoke_policy.json")
  ecs_run_task_policy_hash    = filesha256("${path.module}/../modules/policies/ecs_run_task_policy.json")
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
    }
  ]

  additional_tags = merge(var.additional_tags, {
    SecretsManagerPolicyHash = local.secrets_manager_policy_hash
    CloudWatchLogsPolicyHash = local.cloudwatch_logs_policy_hash
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
        odds_updater_function_arn    = aws_lambda_function.odds_updater.arn
        fixture_updater_function_arn = aws_lambda_function.fixture_updater.arn
      })
    },
    {
      name = "run-ecs-task"
      policy = templatefile("${path.module}/../modules/policies/ecs_run_task_policy.json", {
        daily_harvest_task_definition_arn = aws_ecs_task_definition.daily_harvest.arn
        ecs_cluster_arn                   = data.terraform_remote_state.root.outputs.ecs_cluster_arn
        ecs_task_execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
        ecs_task_role_arn                 = module.batch_scraper_ecs_task_role.role_arn
      })
    }
  ]

  additional_tags = merge(var.additional_tags, {
    LambdaInvokePolicyHash = local.lambda_invoke_policy_hash
    EcsRunTaskPolicyHash   = local.ecs_run_task_policy_hash
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "odds_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-odds-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-odds-updater-logs"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_log_group" "fixture_updater" {
  name              = "/aws/lambda/${var.stack_name}-${var.env}-fixture-updater"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-updater-logs"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_log_group" "daily_harvest" {
  name              = "/ecs/${var.stack_name}-${var.env}-daily-harvest"
  retention_in_days = 7

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-daily-harvest-logs"
    },
    var.additional_tags
  )
}

# ============================================================================
# LAMBDA FUNCTIONS
# ============================================================================

# Odds Updater Lambda
resource "aws_lambda_function" "odds_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/odds_updater.zip"
  function_name = "${var.stack_name}-${var.env}-odds-updater"
  description   = "Daily odds updater - runs at 9 AM UTC"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.odds_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 180
  memory_size   = 1024
  architectures = ["arm64"]

  # Track S3 package changes using version_id and etag
  source_code_hash = base64encode(sha256("${data.aws_s3_object.odds_updater.version_id}-${data.aws_s3_object.odds_updater.etag}"))

  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.env
      REDIS_URL   = "redis://${data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint}:6379"
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-odds-updater"
      PackageETag = data.aws_s3_object.odds_updater.etag
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.odds_updater
  ]
}

# Fixture Updater Lambda
resource "aws_lambda_function" "fixture_updater" {
  s3_bucket     = var.lambda_s3_bucket
  s3_key        = "${var.lambda_s3_key_prefix}/fixture_updater.zip"
  function_name = "${var.stack_name}-${var.env}-fixture-updater"
  description   = "Hourly fixture updater - runs every hour"
  role          = module.batch_scraper_lambda_role.role_arn
  handler       = "sipap_batch_scraper.jobs.fixture_updater.lambda_handler"
  runtime       = "python3.12"
  timeout       = 180
  memory_size   = 1024
  architectures = ["arm64"]

  # Track S3 package changes using version_id and etag
  source_code_hash = base64encode(sha256("${data.aws_s3_object.fixture_updater.version_id}-${data.aws_s3_object.fixture_updater.etag}"))

  vpc_config {
    subnet_ids         = data.terraform_remote_state.root.outputs.private_subnet_ids
    security_group_ids = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.env
      REDIS_URL   = "redis://${data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint}:6379"
    }
  }

  tags = merge(
    {
      Name        = "${var.stack_name}-${var.env}-fixture-updater"
      PackageETag = data.aws_s3_object.fixture_updater.etag
    },
    var.additional_tags
  )

  depends_on = [
    aws_cloudwatch_log_group.fixture_updater
  ]
}

# ============================================================================
# ECS TASK DEFINITION
# ============================================================================

resource "aws_ecs_task_definition" "daily_harvest" {
  family                   = "${var.stack_name}-${var.env}-daily-harvest"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.terraform_remote_state.root.outputs.ecs_task_execution_role_arn
  task_role_arn            = module.batch_scraper_ecs_task_role.role_arn

  container_definitions = jsonencode([
    {
      name      = "daily-harvest"
      image     = "${lookup(data.terraform_remote_state.root.outputs.ecr_repository_urls, "batch-scraper", "")}:latest"
      essential = true
      command   = ["python", "-m", "sipap_batch_scraper.jobs.daily_harvest"]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.env
        },
        {
          name  = "REDIS_URL"
          value = "redis://${data.terraform_remote_state.root.outputs.elasticache_configuration_endpoint}:6379"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.daily_harvest.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-daily-harvest"
    },
    var.additional_tags
  )
}

# ============================================================================
# EVENTBRIDGE SCHEDULES
# ============================================================================

# Daily Harvest Schedule (12:00 AM UTC)
resource "aws_cloudwatch_event_rule" "daily_harvest" {
  name                = "${var.stack_name}-${var.env}-daily-harvest-schedule"
  description         = "Daily harvest - runs at 12:00 AM UTC"
  schedule_expression = "cron(0 0 * * ? *)"
  state               = "ENABLED"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-daily-harvest-schedule"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_event_target" "daily_harvest" {
  rule      = aws_cloudwatch_event_rule.daily_harvest.name
  target_id = "DailyHarvestFargate"
  arn       = data.terraform_remote_state.root.outputs.ecs_cluster_arn
  role_arn  = module.batch_scraper_eventbridge_role.role_arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.daily_harvest.arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = data.terraform_remote_state.root.outputs.private_subnet_ids
      security_groups  = [data.terraform_remote_state.root.outputs.ecs_tasks_sg_id]
      assign_public_ip = false
    }
  }
}

# Odds Updater Schedule (9:00 AM UTC daily)
resource "aws_cloudwatch_event_rule" "odds_updater" {
  name                = "${var.stack_name}-${var.env}-odds-updater-schedule"
  description         = "Odds updater - runs daily at 9 AM UTC"
  schedule_expression = "cron(0 9 * * ? *)"
  state               = "ENABLED"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-odds-updater-schedule"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_event_target" "odds_updater" {
  rule      = aws_cloudwatch_event_rule.odds_updater.name
  target_id = "OddsUpdaterLambda"
  arn       = aws_lambda_function.odds_updater.arn
}

resource "aws_lambda_permission" "odds_updater_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.odds_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.odds_updater.arn
}

# Fixture Updater Schedule (Hourly)
resource "aws_cloudwatch_event_rule" "fixture_updater" {
  name                = "${var.stack_name}-${var.env}-fixture-updater-schedule"
  description         = "Fixture updater - runs hourly"
  schedule_expression = "rate(1 hour)"
  state               = "ENABLED"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-fixture-updater-schedule"
    },
    var.additional_tags
  )
}

resource "aws_cloudwatch_event_target" "fixture_updater" {
  rule      = aws_cloudwatch_event_rule.fixture_updater.name
  target_id = "FixtureUpdaterLambda"
  arn       = aws_lambda_function.fixture_updater.arn
}

resource "aws_lambda_permission" "fixture_updater_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fixture_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fixture_updater.arn
}
