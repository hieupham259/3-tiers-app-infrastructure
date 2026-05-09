resource "aws_route53_zone" "primary" {
  name = var.primary_domain
  tags = merge(var.tags, {
    Project   = "3-tiers-app"
    ManagedBy = "terraform"
    Scope     = "global"
  })
}
