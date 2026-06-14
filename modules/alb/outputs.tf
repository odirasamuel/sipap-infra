output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.sentinel_lb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB for Route53 records"
  value       = aws_lb.sentinel_lb.zone_id
}

output "dynamic_target_group_arns" {
  description = "ARNs of the dynamically created target groups"
  value = {
    for name, tg in aws_lb_target_group.alb_tg : name => tg.arn
  }
}

output "alb_id" {
  description = "ID of the ALB"
  value       = aws_lb.sentinel_lb.id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.sentinel_lb.arn
}