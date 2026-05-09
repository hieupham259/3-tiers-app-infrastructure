variable "environment" {
  type        = string
  description = "Environment name"
}

variable "service_name" {
  type        = string
  default     = "backend"
  description = "Service name"
}

variable "cluster_name" {
  type        = string
  description = "ECS cluster name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for task ENIs"
}

variable "alb_target_group_arn" {
  type        = string
  description = "ALB target group ARN to register tasks against"
}

variable "alb_security_group_id" {
  type        = string
  description = "ALB security group - granted ingress to the ECS task SG"
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repo URL (image source)"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Default image tag for the initial task. App repo overrides via aws ecs update-service."
}

variable "rds_endpoint" {
  type        = string
  description = "RDS endpoint for the DB_HOST env var"
}

variable "rds_secret_arn" {
  type        = string
  description = "Secrets Manager ARN holding DB credentials"
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Port the container exposes"
}

variable "task_cpu" {
  type        = number
  default     = 512
}

variable "task_memory" {
  type        = number
  default     = 1024
}

variable "desired_count" {
  type        = number
  default     = 1
}

variable "existing_task_exec_role_arn" {
  type        = string
  default     = null
  description = "If set, use an existing task execution role"
}

variable "existing_task_role_arn" {
  type        = string
  default     = null
  description = "If set, use an existing task role"
}

variable "tags" {
  type    = map(string)
  default = {}
}
