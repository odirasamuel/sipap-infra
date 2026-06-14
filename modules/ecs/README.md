# ECS Module

This module creates and manages Amazon ECS (Elastic Container Service) resources for running containerized applications on AWS Fargate.

## Features

- **ECS Cluster**: Fargate-enabled cluster with Container Insights
- **Task Definitions**: Configurable CPU/memory, container specifications
- **ECS Services**: Auto-scaling, load balancer integration, health checks  
- **Service Discovery**: AWS Cloud Map integration for DNS-based service discovery
- **CloudWatch Logging**: Centralized logging for all containers
- **ECS Exec**: Optional debugging access to running containers
- **Deployment Controls**: Circuit breaker, rollback, deployment configuration

## Architecture

```
Internet → ALB → Target Group → ECS Service → Fargate Tasks
                                      ↓
                           Service Discovery ← Cloud Map
                                      ↓
                              CloudWatch Logs
```

## Usage

```hcl
module "ecs" {
  source = "./modules/ecs"

  stack_name             = "myapp"
  env                   = "prod"
  vpc_id                = "vpc-12345678"
  private_subnet_ids    = ["subnet-12345", "subnet-67890"]
  task_execution_role_arn = "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"

  services = [
    {
      name           = "web-app"
      image          = "123456789012.dkr.ecr.us-west-1.amazonaws.com/myapp-prod-web-app:latest"
      cpu            = 512
      memory         = 1024
      desired_count  = 2

      port_mappings = [
        {
          container_port = 8080
          protocol       = "tcp"
        }
      ]

      environment_variables = [
        {
          name  = "APP_ENV"
          value = "production"
        }
      ]

      secrets = [
        {
          name       = "DATABASE_PASSWORD"
          value_from = "arn:aws:secretsmanager:us-west-1:123456789012:secret:db-password-AbCdEf"
        }
      ]

      security_group_ids = ["sg-12345678"]

      load_balancer_config = {
        target_group_arn = "arn:aws:elasticloadbalancing:us-west-1:123456789012:targetgroup/myapp-web-tg/50dc6c495c0c9188"
        container_port   = 8080
      }

      health_check = {
        command      = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 60
      }
    }
  ]

  enable_container_insights = true
  enable_service_discovery = true
  log_retention_days       = 30

  additional_tags = {
    Environment = "production"
    Team        = "devops"
  }
}
```

## CPU/Memory Combinations

Fargate supports specific CPU/Memory combinations:

| CPU (vCPU) | Memory (MB) |
|------------|-------------|
| 256        | 512, 1024, 2048 |
| 512        | 1024-4096 (1GB increments) |
| 1024       | 2048-8192 (1GB increments) |
| 2048       | 4096-16384 (1GB increments) |
| 4096       | 8192-30720 (1GB increments) |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stack_name | Name of the stack | string | n/a | yes |
| env | Environment name | string | n/a | yes |
| vpc_id | VPC ID where ECS cluster will be deployed | string | n/a | yes |
| private_subnet_ids | List of private subnet IDs for ECS tasks | list(string) | n/a | yes |
| task_execution_role_arn | ARN of the ECS task execution role | string | n/a | yes |
| services | List of ECS services to create | list(object) | n/a | yes |
| enable_container_insights | Enable CloudWatch Container Insights | bool | true | no |
| enable_service_discovery | Enable AWS Cloud Map service discovery | bool | true | no |
| enable_execute_command | Enable ECS Exec for debugging | bool | false | no |
| platform_version | Fargate platform version | string | "LATEST" | no |
| log_retention_days | CloudWatch logs retention period | number | 30 | no |
| additional_tags | Additional tags for all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | ECS cluster ID |
| cluster_arn | ECS cluster ARN |
| cluster_name | ECS cluster name |
| service_ids | Map of service names to their IDs |
| service_arns | Map of service names to their ARNs |
| task_definition_arns | Map of service names to their task definition ARNs |
| log_group_names | Map of service names to their CloudWatch log group names |
| service_discovery_namespace_id | Service discovery namespace ID |
| account_id | AWS Account ID |
| region | AWS Region |

## Service Configuration

Each service in the `services` list supports:

### Required Fields
- `name`: Service name
- `image`: Container image URL (ECR recommended)  
- `cpu`: Task CPU allocation (256-4096)
- `memory`: Task memory allocation (512-30720)
- `desired_count`: Number of tasks to run
- `security_group_ids`: Security groups for tasks
- `port_mappings`: Container port configurations

### Optional Fields
- `task_role_arn`: IAM role for application permissions
- `environment_variables`: Environment variable list
- `secrets`: AWS Secrets Manager/SSM integration
- `load_balancer_config`: ALB target group integration
- `health_check`: Container health check configuration
- `deployment_configuration`: Rolling deployment settings

## Security Best Practices

1. **Network Isolation**: Deploy tasks in private subnets only
2. **IAM Least Privilege**: Use separate task roles per service
3. **Secrets Management**: Store sensitive data in AWS Secrets Manager
4. **Image Security**: Enable ECR image scanning
5. **Logging**: Enable CloudWatch Container Insights for monitoring
6. **Access Control**: Limit ECS Exec to development environments only