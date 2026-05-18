variable "environment" {
  type        = string
  description = "Environment name (development, production)"
}

variable "region" {
  type        = string
  description = "AWS region"
}

# --- Network ---
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC when self-created"
}

variable "existing_vpc_id" {
  type        = string
  default     = null
  description = "If set, use an existing VPC"
}

variable "existing_private_subnet_ids" {
  type    = list(string)
  default = null
}

variable "existing_public_subnet_ids" {
  type    = list(string)
  default = null
}

# --- RDS ---
variable "rds_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "rds_storage_gb" {
  type    = number
  default = 20
}

variable "rds_backup_retention_days" {
  type    = number
  default = 7
}

variable "rds_deletion_protection" {
  type    = bool
  default = true
}

variable "rds_master_password" {
  type        = string
  description = "RDS master password forwarded from env-level TF_VAR. Sourced from GitHub Environment Secret RDS_MASTER_PASSWORD (per env)."
  sensitive   = true
  nullable    = false
}

# --- ECS ---
variable "ecs_task_cpu" {
  type    = number
  default = 512
}

variable "ecs_task_memory" {
  type    = number
  default = 1024
}

variable "ecs_desired_count" {
  type    = number
  default = 1
}

# --- Domain & ACM ---
variable "domain_name" {
  type        = string
  default     = null
  description = "FQDN for the frontend (e.g. development.myapp.example.com)"
}

variable "alb_acm_cert_arn" {
  type        = string
  default     = null
  description = "ACM cert ARN for the ALB (same region)"
}

variable "frontend_cf_cert_arn" {
  type        = string
  default     = null
  description = "ACM cert ARN for CloudFront (us-east-1)"
}

variable "hosted_zone_id" {
  type        = string
  default     = null
  description = "Route53 hosted zone ID (BYO)"
}

# --- Observability ---
variable "alarm_sns_topic_arn" {
  type        = string
  default     = null
  nullable    = true
  description = "SNS topic ARN that CloudWatch alarms publish to. Leave null to skip alarm actions (alarms still fire and appear in the console)."
}

# --- Tags ---
variable "tags" {
  type    = map(string)
  default = {}
}

variable "repository" {
  type        = string
  description = "Source code repository name; tagged on all resources for traceability."
}
