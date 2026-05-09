output "oidc_provider_arn" {
  description = "ARN of the OIDC provider (already created by CFN bootstrap)"
  value       = data.aws_iam_openid_connect_provider.github.arn
}
