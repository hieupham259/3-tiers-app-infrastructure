variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where RDS runs"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private isolated subnets for the DB subnet group (>= 2)"
}

variable "ingress_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to ingress on 5432 (e.g. ECS task SG)"
}

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "PostgreSQL major.minor version"
}

variable "instance_class" {
  type        = string
  default     = "db.t4g.small"
  description = "Instance class (development: db.t4g.small, production: db.r6g.large)"
}

variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Storage GB"
}

variable "max_allocated_storage" {
  type        = number
  default     = 100
  description = "Max storage for autoscaling"
}

variable "multi_az" {
  type        = bool
  default     = false
  description = "Multi-AZ deployment (production: true)"
}

variable "backup_retention_days" {
  type        = number
  default     = 7
  description = "Retention days for automated backups"
}

variable "db_name" {
  type        = string
  default     = "appdb"
  description = "Initial database name"
}

variable "master_username" {
  type        = string
  default     = "app_admin"
  description = "Master username"
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Enable deletion protection (production: must be true)"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip snapshot on destroy (development may set true)"
}

variable "existing_kms_key_arn" {
  type        = string
  default     = null
  description = "If set, use this KMS key instead of creating one"
}

variable "tags" {
  type    = map(string)
  default = {}
}
