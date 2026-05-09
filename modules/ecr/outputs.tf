output "repository_url" {
  description = "ECR repository URL (used by ECS tasks to pull the image)"
  value       = local.create_repo ? aws_ecr_repository.this[0].repository_url : var.existing_ecr_repo_url
}

output "repository_name" {
  description = "ECR repository name"
  value       = local.create_repo ? aws_ecr_repository.this[0].name : var.repo_name
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = local.create_repo ? aws_ecr_repository.this[0].arn : null
}
