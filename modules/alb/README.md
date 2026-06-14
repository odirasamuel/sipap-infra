# Application Load Balancer (ALB) Module

This Terraform module creates an AWS Application Load Balancer (ALB) with associated target groups and listeners for multiple services. The module is designed to handle multiple services through a single ALB configuration with dynamic target group creation.

## Features

- **Multi-Service Support**: Creates target groups and listeners for multiple services dynamically
- **Health Checks**: Configurable health checks with custom paths and parameters
- **Session Stickiness**: Cookie-based session stickiness enabled by default
- **Internal/External**: Supports both internal and internet-facing load balancers
- **Cross-Zone Load Balancing**: Enabled for better traffic distribution
- **Flexible Target Types**: Supports both instance and IP target types

## Usage

```hcl
module "alb" {
  source = "./modules/alb"
  
  stack_name      = "my-stack"
  env             = "production"
  aws_region      = "us-east-1"
  stack_tool      = "int-alb"
  vpc_id          = "vpc-12345678"
  subnet_ids      = ["subnet-12345678", "subnet-87654321"]
  security_groups = ["sg-12345678"]
  alb_internal    = true
  
  alb_services = [
    {
      name                = "selenium-hub"
      stack_name          = "my-stack"
      env                 = "production"
      aws_region          = "us-east-1"
      stack_tool          = "selenium"
      protocol            = "HTTP"
      target_type         = "instance"
      port                = 4444
      health_check_path   = "/wd/hub/status"
      health_check_port   = "4444"
      timeout             = 120
      interval            = 300
      healthy_threshold   = 5
      unhealthy_threshold = 5
      enable_health_check = true
    },
    {
      name                = "grafana"
      stack_name          = "my-stack"
      env                 = "production"
      aws_region          = "us-east-1"
      stack_tool          = "grafana"
      protocol            = "HTTP"
      target_type         = "instance"
      port                = 3000
      health_check_path   = "/login"
      enable_health_check = true
    }
  ]
}
```

## Architecture

The ALB module creates:

1. **Application Load Balancer**: Layer 7 load balancer with HTTP/HTTPS support
2. **Target Groups**: One per service with appropriate health checks
3. **Listeners**: One per service port to route traffic to target groups
4. **Session Stickiness**: Cookie-based stickiness for consistent user experience

## Variables

### Required Variables

| Name | Type | Description |
|------|------|-------------|
| `stack_name` | `string` | Name of the stack |
| `env` | `string` | Environment name |
| `aws_region` | `string` | AWS region (must be us-east-1 or us-gov-west-1) |
| `stack_tool` | `string` | SIG tools identifier |
| `vpc_id` | `string` | ID of the VPC |
| `subnet_ids` | `list(string)` | List of subnet IDs for ALB placement |
| `security_groups` | `list(string)` | List of security group IDs |
| `alb_services` | `list(object)` | List of service configurations |

### Optional Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `alb_internal` | `bool` | `false` | Whether the ALB is internal or internet-facing |

### ALB Services Object

Each service in `alb_services` supports:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | `string` | Yes | - | Unique service name |
| `stack_name` | `string` | Yes | - | Stack name |
| `env` | `string` | Yes | - | Environment |
| `aws_region` | `string` | Yes | - | AWS region |
| `stack_tool` | `string` | Yes | - | Tool identifier |
| `protocol` | `string` | Yes | - | Protocol (HTTP/HTTPS) |
| `target_type` | `string` | Yes | - | Target type (instance/ip) |
| `port` | `number` | Yes | - | Service port |
| `health_check_path` | `string` | No | `"/"` | Health check path |
| `health_check_port` | `string` | No | service port | Health check port |
| `timeout` | `number` | No | `120` | Health check timeout |
| `interval` | `number` | No | `300` | Health check interval |
| `healthy_threshold` | `number` | No | `5` | Healthy threshold count |
| `unhealthy_threshold` | `number` | No | `5` | Unhealthy threshold count |
| `enable_health_check` | `bool` | No | `false` | Enable health checks |

## Outputs

| Name | Description |
|------|-------------|
| `alb_dns_name` | DNS name of the ALB |
| `alb_id` | ID of the ALB |
| `dynamic_target_group_arns` | Map of service names to target group ARNs |

## Example Service Configurations

### Selenium Hub
```hcl
{
  name                = "selenium-hub"
  protocol            = "HTTP"
  port                = 4444
  health_check_path   = "/wd/hub/status"
  enable_health_check = true
}
```

### Grafana
```hcl
{
  name                = "grafana"
  protocol            = "HTTP"
  port                = 3000
  health_check_path   = "/login"
  enable_health_check = true
}
```

### Prometheus
```hcl
{
  name                = "prometheus" 
  protocol            = "HTTP"
  port                = 9090
  health_check_path   = "/-/healthy"
  enable_health_check = true
}
```

## Features

### Session Stickiness
- **Type**: Load balancer cookie
- **Duration**: 24 hours (86400 seconds)
- **Enabled**: By default for all services

### Health Checks
- **Configurable**: Per-service health check configuration
- **Custom Paths**: Support for service-specific health check endpoints
- **Flexible Timing**: Configurable timeout, interval, and threshold values

### Security
- **Security Groups**: Applied at ALB level
- **Internal/External**: Configurable scheme for internal or internet-facing deployment

## Integration with Auto Scaling Groups

The ALB integrates seamlessly with Auto Scaling Groups:

1. **Target Registration**: ASG automatically registers/deregisters instances
2. **Health Checks**: ALB health checks influence ASG health decisions
3. **Traffic Distribution**: Distributes traffic across healthy instances

## Best Practices

### Regional Deployment
1. Deploy separate ALBs per region for isolation
2. Use Route 53 for global load balancing with:
   - Latency-based routing for performance
   - Failover routing for disaster recovery

### HTTPS Termination
To implement HTTPS termination:
1. Obtain/import SSL certificate in ACM
2. Add HTTPS listener on port 443
3. Redirect HTTP (port 80) to HTTPS
4. Update security groups accordingly

```hcl
# Example HTTPS configuration (requires additional listener resources)
{
  name     = "grafana-https"
  protocol = "HTTPS"
  port     = 443
  # SSL certificate ARN required
}
```

### Monitoring
- Enable ALB access logs to S3
- Monitor target group health in CloudWatch
- Set up CloudWatch alarms for unhealthy targets

## Troubleshooting

### Common Issues

1. **Health Check Failures**
   - Verify health check path returns 200 status
   - Check security group rules allow health check traffic
   - Ensure service is running on specified port

2. **Target Registration Issues**
   - Verify target group configuration matches ASG
   - Check subnet configuration for target availability
   - Ensure proper IAM permissions for ASG integration

3. **Connectivity Issues**
   - Verify security group rules for ALB and targets
   - Check subnet routing and NAT gateway configuration
   - Ensure load balancer scheme matches network requirements

### Debugging Commands

```bash
# Check ALB status
aws elbv2 describe-load-balancers --names <alb-name>

# Check target group health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# View ALB listeners
aws elbv2 describe-listeners --load-balancer-arn <alb-arn>
```

## Version Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 4.0 |