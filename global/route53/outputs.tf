output "hosted_zone_id" {
  description = "Route53 hosted zone ID for the primary domain"
  value       = aws_route53_zone.primary.zone_id
}

output "name_servers" {
  description = "Name servers to enter at the registrar"
  value       = aws_route53_zone.primary.name_servers
}
