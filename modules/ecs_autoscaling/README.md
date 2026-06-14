# ECS Auto Scaling Module

This module creates and manages Application Auto Scaling resources for ECS services, providing automatic scaling based on CPU, memory, custom metrics, and scheduled patterns.

## Features

- **Target Tracking Scaling**: Automatic scaling based on CPU and memory utilization
- **Custom Metric Scaling**: Scale based on ALB request count or custom CloudWatch metrics
- **Step Scaling**: Advanced scaling with multiple thresholds and adjustments
- **Scheduled Scaling**: Predictable scaling patterns for known traffic patterns
- **CloudWatch Integration**: Comprehensive monitoring and alerting
- **Production Ready**: Battle-tested scaling policies and cooldown configurations

## Architecture

```
CloudWatch Metrics → Auto Scaling Policies → ECS Service → Task Count Changes
        ↓
CloudWatch Alarms → Step Scaling Actions → Immediate Response
        ↓
Scheduled Actions → Predictive Scaling → Proactive Adjustments
```

## Scaling Types

### 1. Target Tracking Scaling (Recommended)
Automatically adjusts capacity to maintain target metric values:
- **CPU Utilization**: Maintains target CPU percentage
- **Memory Utilization**: Maintains target memory percentage
- **ALB Request Count**: Maintains requests per target

### 2. Step Scaling (Advanced)
Scales based on multiple thresholds with different adjustment sizes:
- **Gradual Response**: Small increases for minor spikes
- **Aggressive Response**: Large increases for major spikes
- **CloudWatch Alarms**: Triggers scaling based on custom thresholds

### 3. Scheduled Scaling
Proactive scaling for predictable patterns:
- **Business Hours**: Scale up during work hours
- **Batch Processing**: Scale for scheduled jobs
- **Maintenance Windows**: Scale down during maintenance

## Usage

### Basic CPU-based Scaling
```hcl
module "ecs_autoscaling" {
  source = "./modules/ecs_autoscaling"

  stack_name       = "myapp"
  env             = "prod"
  cluster_name    = "myapp-prod-cluster"
  service_role_arn = "arn:aws:iam::123456789012:role/aws-application-autoscaling-ecs-service-role"

  services = [
    {
      name         = "web-app"
      service_name = "myapp-prod-web-app"
      min_capacity = 2
      max_capacity = 10

      enable_cpu_scaling = true
      cpu_target_value   = 70

      scale_in_cooldown  = 300
      scale_out_cooldown = 300
    }
  ]

  additional_tags = {
    Environment = "production"
    Team        = "devops"
  }
}
```

### Advanced Multi-Metric Scaling
```hcl
module "ecs_autoscaling" {
  source = "./modules/ecs_autoscaling"

  stack_name       = "myapp"
  env             = "prod"
  cluster_name    = "myapp-prod-cluster"
  service_role_arn = "arn:aws:iam::123456789012:role/aws-application-autoscaling-ecs-service-role"

  services = [
    {
      name         = "api-service"
      service_name = "myapp-prod-api-service"
      min_capacity = 3
      max_capacity = 20

      # CPU-based scaling
      enable_cpu_scaling = true
      cpu_target_value   = 60

      # Memory-based scaling
      enable_memory_scaling = true
      memory_target_value   = 75

      # Custom ALB request count scaling
      custom_metric_scaling = {
        target_value = 1000
        predefined_metric = {
          metric_type     = "ALBRequestCountPerTarget"
          resource_label  = "app/myapp-alb/50dc6c495c0c9188/targetgroup/myapp-api-tg/73e2d6bc24d8a067"
        }
      }

      # Step scaling for burst traffic
      enable_step_scaling = true
      cpu_high_threshold = 85
      cpu_low_threshold  = 25
      
      step_scaling_config = {
        scale_up_adjustments = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 3
          }
        ]
        scale_down_adjustments = [
          {
            metric_interval_upper_bound = 0
            scaling_adjustment          = -1
          }
        ]
      }

      # Scheduled scaling for business hours
      scheduled_scaling = [
        {
          name         = "business-hours-up"
          schedule     = "cron(0 8 * * MON-FRI)"
          min_capacity = 5
          max_capacity = 20
        },
        {
          name         = "business-hours-down"
          schedule     = "cron(0 18 * * MON-FRI)"
          min_capacity = 2
          max_capacity = 10
        }
      ]
    }
  ]
}
```

### Custom Metric Scaling
```hcl
services = [
  {
    name         = "worker-service"
    service_name = "myapp-prod-worker"
    min_capacity = 1
    max_capacity = 50

    custom_metric_scaling = {
      target_value = 100
      custom_metric = {
        metric_name = "ApproximateNumberOfMessages"
        namespace   = "AWS/SQS"
        statistic   = "Average"
        dimensions = [
          {
            name  = "QueueName"
            value = "myapp-work-queue"
          }
        ]
      }
    }
  }
]
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| stack_name | Name of the stack | string | n/a | yes |
| env | Environment name | string | n/a | yes |
| cluster_name | Name of the ECS cluster | string | n/a | yes |
| service_role_arn | ARN of the service role for auto scaling | string | n/a | yes |
| services | List of ECS services to configure | list(object) | n/a | yes |
| enable_cloudwatch_alarms | Enable CloudWatch alarms | bool | true | no |
| alarm_evaluation_periods | CloudWatch alarm evaluation periods | number | 2 | no |
| alarm_period | CloudWatch alarm period in seconds | number | 300 | no |
| additional_tags | Additional tags for resources | map(string) | {} | no |

## Service Configuration

Each service supports the following configuration:

### Required Fields
- `name`: Unique identifier for the service
- `service_name`: Actual ECS service name
- `min_capacity`: Minimum number of tasks (≥ 1)
- `max_capacity`: Maximum number of tasks (≥ min_capacity)

### Scaling Options
- `enable_cpu_scaling`: Enable CPU-based target tracking (default: true)
- `cpu_target_value`: Target CPU utilization percentage (10-90, default: 70)
- `enable_memory_scaling`: Enable memory-based target tracking (default: false)
- `memory_target_value`: Target memory utilization percentage (10-90, default: 80)
- `scale_in_cooldown`: Cooldown period for scaling in (default: 300 seconds)
- `scale_out_cooldown`: Cooldown period for scaling out (default: 300 seconds)

### Advanced Scaling
- `enable_step_scaling`: Enable step scaling with CloudWatch alarms
- `cpu_high_threshold`: CPU threshold for scaling up alarm
- `cpu_low_threshold`: CPU threshold for scaling down alarm
- `step_scaling_config`: Define scaling adjustments for different thresholds

### Custom Metrics
- `custom_metric_scaling`: Configure scaling based on custom CloudWatch metrics
- Support for both predefined metrics (ALB, etc.) and custom metrics

### Scheduled Scaling
- `scheduled_scaling`: List of scheduled scaling actions using cron expressions

## Outputs

| Name | Description |
|------|-------------|
| autoscaling_target_arns | Auto scaling target ARNs by service |
| cpu_scaling_policy_arns | CPU scaling policy ARNs by service |
| memory_scaling_policy_arns | Memory scaling policy ARNs by service |
| custom_metric_scaling_policy_arns | Custom metric scaling policy ARNs |
| step_scaling_up_policy_arns | Step scaling up policy ARNs |
| step_scaling_down_policy_arns | Step scaling down policy ARNs |
| high_cpu_alarm_arns | High CPU alarm ARNs by service |
| low_cpu_alarm_arns | Low CPU alarm ARNs by service |
| scaling_summary | Complete scaling configuration summary |

## Best Practices

### 1. Scaling Strategy Selection
- **CPU Scaling**: Best for compute-intensive applications
- **Memory Scaling**: Ideal for memory-intensive workloads
- **Custom Metrics**: Use for application-specific metrics (queue depth, request count)
- **Scheduled Scaling**: Perfect for predictable traffic patterns

### 2. Cooldown Configuration
- **Scale Out**: Shorter cooldowns (60-300 seconds) for faster response to spikes
- **Scale In**: Longer cooldowns (300-600 seconds) to avoid thrashing
- **Production**: Use conservative cooldowns to ensure stability

### 3. Target Values
- **CPU**: 60-80% for most applications (70% recommended)
- **Memory**: 70-85% for most applications (80% recommended)
- **Custom**: Set based on application performance characteristics

### 4. Capacity Planning
- **Min Capacity**: Set to handle base load with some buffer
- **Max Capacity**: Consider cost constraints and downstream system limits
- **Safety Margin**: Always plan for 20-30% above expected peak load

## Troubleshooting

### Scaling Not Triggered
1. Check CloudWatch metrics are being published
2. Verify scaling policies are correctly configured
3. Ensure cooldown periods aren't preventing scaling
4. Confirm service role has proper permissions

### Over/Under Scaling
1. Adjust target values based on application behavior
2. Review cooldown periods
3. Check for competing scaling policies
4. Monitor CloudWatch metrics for patterns

### Step Scaling Issues
1. Verify CloudWatch alarms are configured correctly
2. Check alarm thresholds are appropriate
3. Ensure step adjustments make sense for your use case
4. Monitor alarm state changes in CloudWatch

## Monitoring

Key metrics to monitor:
- Service desired/running task count
- CPU and memory utilization
- Scaling activity (scale out/in events)
- CloudWatch alarm states
- Application performance during scaling events