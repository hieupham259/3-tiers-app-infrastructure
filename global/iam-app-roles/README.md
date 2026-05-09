# global/iam-app-roles

> **Note:** In the current Hybrid architecture, app-repo roles (`gha-backend-deploy`, `gha-frontend-deploy`) are provisioned **via CloudFormation** (`bootstrap/03-github-oidc-roles.yaml`). This Terraform folder is NOT used.

## When to use

- You need to add a role beyond the 4 already in place (`gha-infra-plan`, `gha-infra-apply`, `gha-backend-deploy`, `gha-frontend-deploy`)
- You want to manage a role via Terraform instead of CFN (e.g. an app team needs to iterate quickly on the role policy)

## When NOT to use

- In the current workflow - all 4 roles are already created by CFN and sufficient for the 3 repos.

## Skeleton (placeholder)

Folder is empty - add `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf` only when a new role is genuinely needed.
