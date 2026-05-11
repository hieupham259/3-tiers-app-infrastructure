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

## Terraform layout and `terraform init` flow

Terraform always initializes from a **root module** - the directory you `cd` into and run `terraform init` in. This repository has three root modules:

- `envs/development/` - root module for the development account
- `envs/production/` - root module for the production account
- `global/route53/` - root module for cross-env resources (Route53 primary zone)

`envs/_shared/` and everything under `modules/` are **not** root modules. They are local child modules consumed by the roots through `source = "../_shared"` and `source = "../../modules/<name>"`. Never run `terraform init` inside them.

Per the branch-per-environment model, the `development` branch deploys `envs/development/` and the `production` branch deploys `envs/production/`. There are no Terraform workspaces.

### What happens during `terraform init` in `envs/development/`

Terraform does not care about file names; it loads every `*.tf` file in the root module together. The logical sequence is:

1. **Parse every `*.tf` in the root directory** (`envs/development/`):
   - `backend.tf` declares the S3 backend (state key `3-tiers-app/development/terraform.tfstate`, KMS alias `alias/tfstate`, S3-native locking via `use_lockfile = true`).
   - `providers.tf` declares two AWS providers: the default one parameterized by `var.region`, plus an `us_east_1` alias for CloudFront ACM certificates.
   - `variables.tf` declares the root inputs.
   - `main.tf` instantiates a single module `module "stack" { source = "../_shared" ... }` and forwards every variable straight through.
2. **Initialize the S3 backend** - Terraform must configure the backend before doing anything else, so `backend.tf` is the file that effectively kicks off init.
3. **Resolve `module.stack`** by descending into `envs/_shared/`:
   - `versions.tf` pins `aws ~> 5.70`, `random ~> 3.6`, and `terraform >= 1.11`.
   - `main.tf` fans out to nine child modules: `network`, `ecr_backend`, `alb`, `ecs_cluster`, `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability`.
   - `outputs.tf` writes runtime values to SSM Parameter Store under `/3-tiers-app/<env>/...` and exposes a few root-level `output` blocks.
4. **Resolve each child module** under `modules/<name>/` - local modules need no separate init.
5. **Download providers** from the registry into `.terraform/providers/`.
6. **Write `.terraform.lock.hcl`** in the root module to pin provider checksums.

Init in `envs/production/` follows the same flow but binds the backend to the production state key and the provider region to the production region.

### Folder responsibilities

#### `envs/_shared/` - shared stack definition

The single source of truth for the application stack: VPC, ALB, ECS cluster, ECS service, RDS, ECR, IAM app roles, CloudFront frontend, observability, and SSM publishing. It is consumed by both `envs/development/main.tf` and `envs/production/main.tf` via `source = "../_shared"`. This is the mechanism that keeps the two environments identical at the code level.

#### `envs/development/` and `envs/production/` - per-env root modules

Each environment directory holds only four files. After every promotion the two directories are byte-identical except for three files:

- `backend.tf` - **differs**: state key (`/development/` vs `/production/`) and, if applicable, bucket or account.
- `providers.tf` - **differs**: region and default tags.
- `terraform.tfvars` - **differs**: input values (CIDR, instance class, multi-AZ, domain, etc.).
- `main.tf` and `variables.tf` - **identical** across envs; their only job is to forward all `var.*` into `module "stack" { source = "../_shared" }`.

`scripts/verify-envs-in-sync.sh` enforces this invariant in CI.

#### `global/` - cross-environment resources

Resources that do not belong to any single environment. `global/route53/` is an independent root module with its own `versions.tf`, `main.tf`, and (when wired up) its own backend, applied on its own schedule. It hosts singletons such as the project-wide primary Route53 hosted zone that both envs delegate NS records to.

#### `modules/` - reusable building blocks

Local Terraform modules consumed by `envs/_shared/`:

- `network` - VPC, subnets, routing, NAT
- `alb` - public ALB, target group, listener, security group
- `ecs-cluster` - Fargate cluster
- `ecs-service` - task definition, service, security group
- `ecr` - container image repository
- `rds` - PostgreSQL instance, secret, subnet group
- `iam-app-roles` - task and task-execution roles
- `iam-github-oidc` - GitHub Actions OIDC roles
- `frontend-cdn` - S3 bucket, CloudFront distribution, OAC
- `observability` - CloudWatch log groups, alarms

Each module follows the `main.tf` / `variables.tf` / `outputs.tf` / `versions.tf` layout and the `${var.environment}-<resource>-<role>` naming convention.

### How the folders wire together

```
GitHub Actions (branch development)
        |
        v
   cd envs/development            <-- the real root module
        | backend.tf  ----> S3 tfstate (key /development/)
        | providers.tf ---> AWS development account
        | variables.tf + terraform.tfvars
        | main.tf
        v
   module "stack" -> envs/_shared/    <-- one stack definition for every env
        |
        +-- module "network"        -> modules/network/
        +-- module "alb"            -> modules/alb/
        +-- module "ecs_cluster"    -> modules/ecs-cluster/
        +-- module "ecs_service"    -> modules/ecs-service/
        +-- module "rds"            -> modules/rds/
        +-- module "ecr_backend"    -> modules/ecr/
        +-- module "iam_app_roles"  -> modules/iam-app-roles/
        +-- module "frontend_cdn"   -> modules/frontend-cdn/
        +-- module "observability"  -> modules/observability/

   (fully independent root, separate state)

GitHub Actions (global workflow)
        |
        v
   cd global/route53            <-- separate root module, separate state
```

Inside one environment, `envs/_shared/main.tf` wires module outputs to module inputs:

- `network` exposes `vpc_id`, `public_subnet_ids`, `private_subnet_ids` to `alb`, `rds`, and `ecs_service`.
- `alb` exposes `target_group_arn` and `security_group_id` to `ecs_service`.
- `ecs_cluster` exposes `cluster_name` to `ecs_service` and `observability`.
- `rds` exposes `secret_arn`, `endpoint`, and `db_instance_id` to `iam_app_roles`, `ecs_service`, and `observability`.
- `frontend_cdn` exposes `bucket_arn`, `bucket_name`, and `distribution_id` to `iam_app_roles`, `observability`, and the SSM publishing block.
- `ecs_service` exposes `security_group_id` back to `rds` as `ingress_security_group_ids`.
- `envs/_shared/outputs.tf` publishes runtime values to SSM Parameter Store at `/3-tiers-app/<env>/...` so the application repositories (frontend, backend) can read them at deploy time.

Environment isolation is achieved purely through:

1. Two different root directories, so two independent `terraform init` runs and two independent `.terraform/` caches.
2. Two different backend state keys, so two independent state files.
3. Two long-lived git branches, so two independent OIDC roles and two independent AWS accounts.
4. No Terraform workspaces and no cross-env data references; `global/` is also a separate root so it never gets pulled into either env's state.

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
