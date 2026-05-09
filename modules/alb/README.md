# Module: alb

Application Load Balancer + listeners (HTTP redirect -> HTTPS) + target group.

## Features

- HTTP (80) auto-redirects to HTTPS (443) with HTTP 301
- HTTPS listener is only created when `existing_acm_cert_arn != null`
- TLS policy: `ElasticLoadBalancing TLS 1.3 (ELBSecurityPolicy-TLS13-1-2-2021-06)`
- Target group `target_type = ip` (required by Fargate awsvpc mode)
- Health check `/health` (configured via `health_check_path`)
- Deletion protection enabled

## BYO ACM cert

The ALB ACM cert must live in the same region (not us-east-1 like CloudFront). Pass `existing_acm_cert_arn` from the env layer.

## Usage

```hcl
module "alb" {
  source                = "../../modules/alb"
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  existing_acm_cert_arn = var.alb_acm_cert_arn
}
```
