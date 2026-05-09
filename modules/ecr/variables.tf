variable "environment" {
  type        = string
  description = "Environment name (development, production)"
}

variable "repo_name" {
  type        = string
  description = "ECR repository name (e.g. 3-tiers-app-backend)"
}

variable "image_retention_count" {
  type        = number
  default     = 30
  description = "Number of image tags to retain before the lifecycle policy deletes them"
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Enable vulnerability scanning when an image is pushed"
}

variable "existing_ecr_repo_url" {
  type        = string
  default     = null
  description = "If set, use an existing ECR repo instead of creating a new one"
}

variable "tags" {
  type    = map(string)
  default = {}
}
