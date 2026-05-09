output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.this.id
}

output "task_definition_family" {
  description = "Task definition family (for aws ecs register-task-definition)"
  value       = aws_ecs_task_definition.this.family
}

output "security_group_id" {
  description = "Task ENI security group ID (RDS must allow ingress from this SG)"
  value       = aws_security_group.task.id
}

output "log_group_name" {
  description = "CloudWatch log group for task logs"
  value       = aws_cloudwatch_log_group.this.name
}
