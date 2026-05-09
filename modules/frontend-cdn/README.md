# Module: frontend-cdn

S3 bucket (private) + CloudFront distribution with Origin Access Control (OAC).

## Features

- S3 bucket fully private (Block Public Access ON), versioning + SSE
- CloudFront OAC (modern replacement for the deprecated OAI) - only CloudFront can GetObject
- SPA routing: 403/404 -> `/index.html` (for React/Vue Router)
- Bucket name pattern: `3-tiers-app-frontend-<AWS_ACCOUNT_ID>` (globally unique)
- Custom domain via `domain_name` + `existing_acm_cert_arn` (cert must be in **us-east-1**)
- Optional: Route53 alias record when `existing_hosted_zone_id` is set

## ACM cert location

> CloudFront requires the ACM cert in `us-east-1` (N. Virginia). Create a separate cert in that region; do NOT share it with the ALB cert (ALB cert lives in `us-east-1`).

## Usage

```hcl
module "frontend_cdn" {
  source                  = "../../modules/frontend-cdn"
  environment             = var.environment
  domain_name             = var.domain_name
  existing_acm_cert_arn   = var.frontend_cf_cert_arn  # us-east-1
  existing_hosted_zone_id = var.hosted_zone_id
}
```
