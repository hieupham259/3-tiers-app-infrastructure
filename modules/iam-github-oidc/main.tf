# NOTE: In the current architecture, the OIDC provider + roles are provisioned
# via CloudFormation (bootstrap/03-github-oidc-roles.yaml). This module is NOT
# wired into the env layer; it is kept as a reference / fallback in case we
# later migrate the OIDC roles fully to Terraform.
#
# If you do want to use it: data-source lookup the OIDC provider created by
# CFN, then add Terraform-managed roles alongside the CFN-managed ones.

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
