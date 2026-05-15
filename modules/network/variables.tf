variable "environment" {
  type        = string
  description = "Environment name (development, production)"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC when self-created (ignored if existing_vpc_id != null)"
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of AZs the VPC spans. Default 2 to satisfy ALB and RDS DB Subnet Group requirements."
}

# --- BYO (Bring Your Own) - accept pre-existing VPC/subnets ---
variable "existing_vpc_id" {
  type        = string
  default     = null
  description = "If set, use this VPC instead of creating a new one"
}

variable "existing_private_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Existing private subnets (required when existing_vpc_id != null)"
}

variable "existing_public_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Existing public subnets (required when existing_vpc_id != null)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags applied to resources"
}
