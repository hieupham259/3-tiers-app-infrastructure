output "ecs_cpu_alarm_arn" {
  description = "ARN of the ECS CPU alarm"
  value       = aws_cloudwatch_metric_alarm.ecs_cpu_high.arn
}

output "rds_connections_alarm_arn" {
  description = "ARN of the RDS connections alarm"
  value       = aws_cloudwatch_metric_alarm.rds_connections_high.arn
}

output "alb_5xx_alarm_arn" {
  description = "ARN of the ALB 5xx alarm"
  value       = aws_cloudwatch_metric_alarm.alb_5xx.arn
}
