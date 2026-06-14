# Description: This module creates a security group in AWS with dynamic ingress and egress rules.
resource "aws_security_group" "sentinel_sg" {
  name        = "${var.stack_name}-${var.env}-${var.stack_tool}-sg"
  description = "Security group for Sentinel application(s)"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = each

    content {
      description      = each.value.description
      from_port        = each.value.from_port
      to_port          = each.value.to_port
      protocol         = each.value.protocol
      cidr_blocks      = each.value.cidr_blocks
      ipv6_cidr_blocks = each.value.ipv6_cidr_blocks
      security_groups  = each.value.security_groups
    }
  }

  dynamic "egress" {
    for_each = var.egress_rules
    iterator = each

    content {
      description      = each.value.description
      from_port        = each.value.from_port
      to_port          = each.value.to_port
      protocol         = each.value.protocol
      cidr_blocks      = each.value.cidr_blocks
      ipv6_cidr_blocks = each.value.ipv6_cidr_blocks
    }
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${var.stack_tool}-sg"
  }, var.additional_tags)
}