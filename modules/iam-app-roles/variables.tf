variable "environment" {
  type        = string
  description = "Environment name"
}

variable "rds_secret_arn" {
  type        = string
  description = "Secrets Manager ARN of the RDS credentials (task exec needs Decrypt)"
}

variable "frontend_bucket_arn" {
  type        = string
  default     = null
  description = "S3 bucket ARN for the frontend (if the app also needs read access)"
}

variable "existing_task_exec_role_arn" {
  type        = string
  default     = null
  description = "If set, use an existing task execution role - the module skips creation"
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
