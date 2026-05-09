output "task_exec_role_arn" {
  description = "Task execution role ARN (for ECS task definition)"
  value       = local.create_exec_role ? aws_iam_role.task_exec[0].arn : var.existing_task_exec_role_arn
}

output "task_role_arn" {
  description = "Task role ARN (for app code)"
  value       = local.create_task_role ? aws_iam_role.task[0].arn : var.existing_task_role_arn
}
