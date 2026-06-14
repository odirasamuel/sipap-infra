# Description: This module creates an ECS cluster with Fargate services, task definitions, and service discovery
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.stack_name}-${var.env}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  dynamic "configuration" {
    for_each = var.enable_execute_command ? [1] : []
    content {
      execute_command_configuration {
        logging = "OVERRIDE"
        log_configuration {
          cloud_watch_encryption_enabled = false
          cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_execute_command[0].name
        }
      }
    }
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-cluster"
  }, var.additional_tags)
}

# CloudWatch Log Group for ECS Execute Command
resource "aws_cloudwatch_log_group" "ecs_execute_command" {
  count = var.enable_execute_command ? 1 : 0

  name              = "/aws/ecs/${var.stack_name}-${var.env}/execute-command"
  retention_in_days = var.log_retention_days

  tags = merge({
    Name = "${var.stack_name}-${var.env}-execute-command-logs"
  }, var.additional_tags)
}


# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  count = var.enable_service_discovery ? 1 : 0

  name = "${var.stack_name}-${var.env}.local"
  vpc  = var.vpc_id

  tags = merge({
    Name = "${var.stack_name}-${var.env}-service-discovery"
  }, var.additional_tags)
}

# Task Definitions
resource "aws_ecs_task_definition" "app" {
  for_each = { for service in var.services : service.name => service }

  family                   = each.value.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = each.value.task_role_arn

  # EFS volumes configuration
  dynamic "volume" {
    for_each = each.value.efs_volumes != null ? each.value.efs_volumes : []
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = volume.value.root_directory
        transit_encryption      = "ENABLED"
        transit_encryption_port = try(volume.value.transit_encryption_port, 2049)

        dynamic "authorization_config" {
          for_each = volume.value.access_point_id != null ? [1] : []
          content {
            access_point_id = volume.value.access_point_id
            iam             = "ENABLED"
          }
        }
      }
    }
  }

  container_definitions = jsonencode([
    merge(
      {
        name      = each.value.name
        image     = each.value.image
        essential = each.value.container_definition_overrides != null ? each.value.container_definition_overrides.essential : true

        portMappings = [
          for port_mapping in each.value.port_mappings : {
            containerPort = port_mapping.container_port
            protocol      = port_mapping.protocol
          }
        ]
      },
      # Add command if specified
      each.value.command != null ? {
        command = each.value.command
      } : {},
      # Add entrypoint if specified
      each.value.entrypoint != null ? {
        entryPoint = each.value.entrypoint
      } : {},
      {

        environment = [
          for env_var in each.value.environment_variables : {
            name  = env_var.name
            value = env_var.value
          }
        ]

        secrets = [
          for secret in each.value.secrets : {
            name      = secret.name
            valueFrom = secret.value_from
          }
        ]

        # Mount points for EFS volumes
        mountPoints = each.value.mount_points != null ? [
          for mp in each.value.mount_points : {
            sourceVolume  = mp.source_volume
            containerPath = mp.container_path
            readOnly      = mp.read_only
          }
        ] : []

        logConfiguration = each.value.container_definition_overrides != null && each.value.container_definition_overrides.logConfiguration != null ? each.value.container_definition_overrides.logConfiguration : {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app[each.key].name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "ecs"
          }
        }

        healthCheck = each.value.container_definition_overrides != null && each.value.container_definition_overrides.healthCheck != null ? each.value.container_definition_overrides.healthCheck : (
          each.value.health_check != null ? {
            command     = each.value.health_check.command
            interval    = each.value.health_check.interval
            timeout     = each.value.health_check.timeout
            retries     = each.value.health_check.retries
            startPeriod = each.value.health_check.start_period
          } : null
        )
      },
      # Add user override if specified
      each.value.container_definition_overrides != null && each.value.container_definition_overrides.user != null ? {
        user = each.value.container_definition_overrides.user
      } : {}
    )
  ])

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-task"
  }, var.additional_tags)
}

# CloudWatch Log Groups for each service
resource "aws_cloudwatch_log_group" "app" {
  for_each = { for service in var.services : service.name => service }

  name              = "/aws/ecs/${var.stack_name}-${var.env}/${each.value.name}"
  retention_in_days = var.log_retention_days

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-logs"
  }, var.additional_tags)
}

# Service Discovery Services
resource "aws_service_discovery_service" "app" {
  for_each = { for service in var.services : service.name => service if var.enable_service_discovery }

  name = each.value.name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main[0].id

    dns_records {
      ttl  = 60
      type = "A"
    }
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-discovery"
  }, var.additional_tags)
}

# ECS Services
resource "aws_ecs_service" "app" {
  for_each = { for service in var.services : service.name => service }

  name            = each.value.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  platform_version = var.platform_version

  deployment_circuit_breaker {
    enable   = each.value.enable_deployment_circuit_breaker
    rollback = each.value.enable_deployment_rollback
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = each.value.deployment_configuration.maximum_percent
  deployment_minimum_healthy_percent = each.value.deployment_configuration.minimum_healthy_percent

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = each.value.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancer_config != null ? [each.value.load_balancer_config] : []
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = each.value.name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.app[each.key].arn
    }
  }

  enable_execute_command = var.enable_execute_command

  depends_on = [
    aws_ecs_task_definition.app
  ]

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${each.value.name}-service"
  }, var.additional_tags)

  lifecycle {
    ignore_changes = [desired_count]
  }
}