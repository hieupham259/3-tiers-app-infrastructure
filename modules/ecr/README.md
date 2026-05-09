# Module: ecr

ECR repository + lifecycle policy.

## Features

- `image_tag_mutability = IMMUTABLE` - prevents tag overwrites (blocks supply-chain attacks)
- Scan on push (Inspector)
- Lifecycle policy: keep N tagged images, delete untagged after 7 days
- BYO support via `existing_ecr_repo_url`

## Usage

```hcl
module "ecr_backend" {
  source      = "../../modules/ecr"
  environment = var.environment
  repo_name   = "3-tiers-app-backend"
}
```
