variable "environment" {
  type        = string
  description = "Environment name"
}

variable "enable_container_insights" {
  type        = bool
  default     = true
  description = "Enable CloudWatch Container Insights for the cluster"
}

variable "capacity_providers" {
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
  description = "Capacity providers attached to the cluster"
}

variable "default_capacity_provider" {
  type        = string
  default     = "FARGATE"
  description = "Default capacity provider"
}

variable "tags" {
  type    = map(string)
  default = {}
}
