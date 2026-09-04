# VPC Gateway Endpoints — S3 and DynamoDB
#
# Gateway endpoints are FREE (no hourly charge, no data processing fee).
# They redirect S3 and DynamoDB traffic from the NAT Gateway through AWS's
# internal network, reducing NAT data-processing costs.
#
# Traffic that no longer goes through NAT after this change:
#   - ECR image layer pulls from S3 (100-500MB per task launch)
#   - CloudWatch log exports to S3 (if configured)
#   - DynamoDB telemetry/session calls (if any)
#   - Any direct S3 SDK calls from ECS tasks
#
# Estimated savings: $2-5/month in NAT data-processing charges.
# Cost of these endpoints: $0/month.
#
# Note: Bedrock, Secrets Manager, and STS cannot use Gateway endpoints
# (they are Interface endpoints at $7.20/month each — deferred).

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-s3-gateway-endpoint"
    },
    var.additional_tags
  )
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-dynamodb-gateway-endpoint"
    },
    var.additional_tags
  )
}
