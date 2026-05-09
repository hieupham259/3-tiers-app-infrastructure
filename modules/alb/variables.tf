variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the ALB (>= 2 AZs)"
}

variable "domain_name" {
  type        = string
  default     = null
  description = "FQDN for the ALB (e.g. api.development.myapp.example.com)"
}

variable "existing_acm_cert_arn" {
  type        = string
  default     = null
  description = "If set, use an existing ACM cert instead of creating one"
}

variable "target_port" {
  type        = number
  default     = 8080
  description = "Port of the ECS task"
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "enable_waf" {
  type        = bool
  default     = false
  description = "Enable WAF (production: should be true)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
