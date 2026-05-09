# Module: iam-github-oidc

> **Note:** In the current Hybrid architecture, the OIDC provider + roles are provisioned **via CloudFormation** (`bootstrap/03-github-oidc-roles.yaml`), NOT this Terraform module. The module is kept as a reference / fallback in case we later migrate to fully Terraform-managed OIDC roles.

## When to use

- Creating a new role for a 4th repo (e.g. `3-tiers-app-mobile`)
- Roles that need more complex policies than CFN provides
- Managing the OIDC role alongside the env stack

## Look up the OIDC provider created by CFN

```hcl
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
```

The new role's trust policy then references `data.aws_iam_openid_connect_provider.github.arn`.
