output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (for CloudWatch metric LoadBalancer dimension)"
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "ALB DNS name (for Route53 alias)"
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "ALB hosted zone ID (for Route53 alias)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "Target group ARN for the ECS service"
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "ALB security group ID (the ECS task SG must allow ingress from this)"
  value       = aws_security_group.alb.id
}
