# --- Publish outputs to SSM Parameter Store for app repos to read ---
resource "aws_ssm_parameter" "ecs_cluster_name" {
  name  = "/3-tiers-app/${var.environment}/ecs/cluster_name"
  type  = "String"
  value = module.ecs_cluster.cluster_name
}

resource "aws_ssm_parameter" "ecs_service_name" {
  name  = "/3-tiers-app/${var.environment}/ecs/service_name"
  type  = "String"
  value = module.ecs_service.service_name
}

resource "aws_ssm_parameter" "ecs_task_definition_family" {
  name  = "/3-tiers-app/${var.environment}/ecs/task_definition_family"
  type  = "String"
  value = module.ecs_service.task_definition_family
}

resource "aws_ssm_parameter" "ecr_backend_url" {
  name  = "/3-tiers-app/${var.environment}/ecr/backend_url"
  type  = "String"
  value = module.ecr_backend.repository_url
}

resource "aws_ssm_parameter" "frontend_bucket" {
  name  = "/3-tiers-app/${var.environment}/frontend/bucket_name"
  type  = "String"
  value = module.frontend_cdn.bucket_name
}

resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  name  = "/3-tiers-app/${var.environment}/frontend/cloudfront_id"
  type  = "String"
  value = module.frontend_cdn.distribution_id
}

resource "aws_ssm_parameter" "alb_dns_name" {
  name  = "/3-tiers-app/${var.environment}/alb/dns_name"
  type  = "String"
  value = module.alb.dns_name
}

# --- Outputs the root layer exposes (for debugging) ---
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "frontend_bucket" {
  description = "Frontend S3 bucket name"
  value       = module.frontend_cdn.bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.frontend_cdn.distribution_id
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
  sensitive   = true
}

output "ecr_backend_url" {
  description = "ECR repository URL for the backend"
  value       = module.ecr_backend.repository_url
}
