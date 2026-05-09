variable "github_org" {
  type        = string
  description = "GitHub organization name"
}

variable "infra_repo" {
  type        = string
  default     = "3-tiers-app-infrastructure"
}

variable "backend_repo" {
  type        = string
  default     = "3-tiers-app-backend"
}

variable "frontend_repo" {
  type        = string
  default     = "3-tiers-app-frontend"
}

variable "allowed_branch" {
  type        = string
  description = "Branch allowed to apply for this account (development for the development account, production for the production account)"
  validation {
    condition     = contains(["development", "production"], var.allowed_branch)
    error_message = "allowed_branch must be either 'development' or 'production'."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
