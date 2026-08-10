# Create a secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "secret" {
  name                           = var.secret_name
  description                    = var.secret_description
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0

  # Only create replica if replica_region is provided
  dynamic "replica" {
    for_each = var.replica_region != null ? [1] : []
    content {
      region = var.replica_region
    }
  }

  tags = merge({
    Name = "${var.secret_name}-secret"
  }, var.additional_tags)
}

# Create a secret version in AWS Secrets Manager
resource "aws_secretsmanager_secret_version" "secret_version" {
  secret_id     = aws_secretsmanager_secret.secret.id
  secret_string = var.secret_string

  # Prevent Terraform from overwriting manually populated secrets
  # After initial creation, secrets should be managed via AWS CLI or Console
  lifecycle {
    ignore_changes = [secret_string]
  }
}
