resource "aws_ssm_parameter" "this" {
  name        = var.parameter_name
  description = var.parameter_description
  type        = var.parameter_type
  value       = var.parameter_value
  tier        = var.parameter_tier

  tags = merge({
    Name      = var.parameter_name
    ManagedBy = "terraform"
    Service   = "api-gateway"
  }, var.additional_tags)
}
