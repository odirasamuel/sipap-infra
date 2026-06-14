# Description: This module creates an AWS Application Load Balancer (ALB) with target groups and listeners.
resource "aws_lb" "sentinel_lb" {
  name                                        = "${var.stack_name}-${var.env}-${var.stack_tool}"
  load_balancer_type                          = "application"
  internal                                    = var.alb_internal
  security_groups                             = var.security_groups
  subnets                                     = var.subnet_ids
  enable_deletion_protection                  = var.enable_deletion_protection
  enable_cross_zone_load_balancing            = true
  enable_tls_version_and_cipher_suite_headers = var.enable_tls_version_and_cipher_suite_headers
  enable_waf_fail_open                        = var.enable_waf_fail_open

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${var.stack_tool}"
  }, var.additional_tags)
}

resource "aws_lb_target_group" "alb_tg" {
  for_each = { for svc in var.alb_services : svc.name => svc }

  # name        = "${each.value.env}-${each.value.aws_region}-${each.key}-tg"
  name        = "${each.value.env}-${each.key}-tg"
  port        = tonumber(each.value.port)
  protocol    = each.value.protocol
  target_type = each.value.target_type
  vpc_id      = var.vpc_id

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }

  dynamic "health_check" {
    for_each = lookup(each.value, "enable_health_check", false) ? [each.value] : []
    content {
      enabled             = lookup(health_check.value, "enabled", true)
      protocol            = lookup(health_check.value, "protocol", each.value.protocol)
      path                = lookup(health_check.value, "health_check_path", "/")
      port                = lookup(health_check.value, "health_check_port", each.value.port)
      timeout             = lookup(health_check.value, "timeout", 120)
      interval            = lookup(health_check.value, "interval", 300)
      healthy_threshold   = lookup(health_check.value, "healthy_threshold", 5)
      unhealthy_threshold = lookup(health_check.value, "unhealthy_threshold", 5)
    }
  }

  tags = merge({
    Name = "${each.value.stack_name}-${each.value.env}-${each.key}-tg"
  }, var.additional_tags)
}

resource "aws_lb_listener" "alb_listener" {
  for_each = { for svc in var.alb_services : svc.name => svc }

  load_balancer_arn = aws_lb.sentinel_lb.arn
  port              = each.value.port
  protocol          = each.value.protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg[each.key].arn
  }

  tags = merge({
    Name = "${each.value.stack_name}-${each.value.env}-${each.key}-tg"

  }, var.additional_tags)
}

# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.sentinel_lb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type = "fixed-response"

#     fixed_response {
#       content_type = "text/plain"
#       message_body = "Fixed response content"
#       status_code  = "200"
#     }
#   }

#   tags = merge({
#     Name = "${var.stack_name}-${var.env}-http"
#   }, var.additional_tags)
# }

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.sentinel_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-http"
  }, var.additional_tags)
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.sentinel_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Unknown host"
      status_code  = "404"
    }
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-https"
  }, var.additional_tags)
}

resource "aws_lb_listener_rule" "https_services" {
  for_each     = { for svc in var.alb_services : svc.name => svc }
  listener_arn = aws_lb_listener.https.arn
  priority = 100 + index(
    [for s in var.alb_services : s.name],
    each.key
  )

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg[each.key].arn
  }

  condition {
    host_header {
      values = [
        "${each.value.name}.${var.domain_name}"
      ]
    }
  }
}