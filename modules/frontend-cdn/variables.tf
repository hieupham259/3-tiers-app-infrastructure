variable "environment" {
  type        = string
  description = "Environment name"
}

variable "domain_name" {
  type        = string
  default     = null
  description = "FQDN for the frontend (e.g. development.myapp.example.com)"
}

variable "existing_acm_cert_arn" {
  type        = string
  default     = null
  description = "ACM cert ARN in us-east-1 (required for the CloudFront custom domain)"
}

variable "existing_hosted_zone_id" {
  type        = string
  default     = null
  description = "Route53 hosted zone ID to create the alias record in"
}

variable "existing_log_bucket_name" {
  type        = string
  default     = null
  description = "S3 bucket for CloudFront access logs (optional)"
}

variable "price_class" {
  type        = string
  default     = "PriceClass_200"
  description = "CloudFront price class (PriceClass_All / PriceClass_200 / PriceClass_100)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
