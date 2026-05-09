output "vpc_id" {
  description = "VPC ID (created or existing)"
  value       = local.create_vpc ? aws_vpc.this[0].id : data.aws_vpc.existing[0].id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = local.create_vpc ? aws_vpc.this[0].cidr_block : data.aws_vpc.existing[0].cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for ECS, RDS)"
  value       = local.create_vpc ? aws_subnet.private[*].id : var.existing_private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB)"
  value       = local.create_vpc ? aws_subnet.public[*].id : var.existing_public_subnet_ids
}

output "azs" {
  description = "Availability zones in use"
  value       = local.azs
}
