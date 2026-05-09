# 3-tiers-app-infrastructure

Terraform infrastructure for a 3-tier app on AWS using the **Hybrid (3 repos)** model.

> Full architecture documentation lives in the root repo:
> - `ARCHITECTURE.md` - infrastructure design + Terraform layout + bootstrap CI/CD
> - `SETUP-GUIDE.md` - step-by-step guide from "two AWS accounts" to "production stack running"

## Summary

- **AWS infrastructure:** VPC, RDS PostgreSQL, ECS Fargate, ALB, ECR, S3 + CloudFront, IAM, CloudWatch
- **Multi-account:** development (`111111111111`) + production (`222222222222`)
- **State:** S3 native locking (Terraform >= 1.11), KMS-encrypted, one bucket per account
- **CI/CD:** GitHub Actions with OIDC (no long-lived access keys)
- **Bootstrap:** 1 manual CFN template upload per account, everything else via CI/CD

## Directory layout

```
.
|-- .github/
|   |-- workflows/                     # GitHub Actions
|   |   |-- bootstrap.yaml             # workflow_dispatch - deploy CFN bootstrap stacks
|   |   |-- terraform-plan.yaml        # PR to development|production - plan both envs
|   |   |-- terraform-apply.yaml       # push to development|production - apply
|   |   |-- terraform-drift.yaml       # nightly drift detection
|   |   `-- cfn-drift-detect.yaml      # weekly CFN drift detection
|   `-- CODEOWNERS
|-- bootstrap/                         # CloudFormation templates
|   |-- 01-trust-anchor.yaml           # MANUAL Console upload (once per account)
|   |-- 02-tfstate-backend.yaml        # CI/CD - S3 state bucket + KMS
|   |-- 03-github-oidc-roles.yaml      # CI/CD - gha-infra-* + app deploy roles
|   `-- README.md
|-- modules/                           # Terraform reusable modules (BYO-aware)
|   |-- network/
|   |-- ecr/
|   |-- rds/
|   |-- ecs-cluster/
|   |-- ecs-service/
|   |-- alb/
|   |-- frontend-cdn/
|   |-- iam-app-roles/
|   |-- iam-github-oidc/
|   `-- observability/
|-- envs/                              # Per-env layer (code identical, only tfvars/backend differ)
|   |-- _shared/                       # SINGLE source of code (main, variables, outputs, versions)
|   |-- development/                   # backend.tf, providers.tf, main.tf, terraform.tfvars
|   `-- production/                    # main.tf IDENTICAL to development
|-- global/                            # Cross-env resources (Route53, app roles)
|   |-- route53/
|   `-- iam-app-roles/
|-- scripts/                           # Helper scripts (run in CI)
|   |-- tf-fmt.sh
|   |-- tf-validate.sh
|   |-- tflint.sh
|   `-- verify-envs-in-sync.sh         # CI guard: envs/development == envs/production
|-- .terraform-version                 # tfenv pin (>= 1.11 for S3 native locking)
|-- .tflint.hcl
|-- .gitignore
|-- Makefile
`-- README.md
```

## Workflow summary

1. **Bootstrap (once per account):**
   - Manual: cloud admin uploads `bootstrap/01-trust-anchor.yaml` via the AWS Console
   - CI: trigger the `bootstrap.yaml` workflow to deploy stacks `02` and `03`
2. **Daily (Terraform):**
   - PR into `development` -> CI plans both envs -> merge -> auto-apply development
   - PR `development -> production` -> CI plans production -> merge -> manual approve -> apply production

See `SETUP-GUIDE.md` (root repo) for detailed phase-by-phase instructions.

## Branch model

- `development` and `production` are two long-lived branches; code is IDENTICAL after every promotion.
- The only differences live under `envs/<env>/{terraform.tfvars,backend.tf,providers.tf}`.
- The `scripts/verify-envs-in-sync.sh` CI guard enforces this.

## Quality gates

- `terraform fmt -check -recursive`
- `terraform validate`
- `tflint --recursive`
- `tfsec` / `checkov` (security scan)
- `verify-envs-in-sync.sh`
