output "db_instance_id" {
  description = "RDS instance identifier (for CloudWatch DBInstanceIdentifier dimension)"
  value       = aws_db_instance.this.id
}

output "endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "RDS hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "secret_arn" {
  description = "Secrets Manager ARN holding master credentials (for ECS task injection)"
  value       = aws_secretsmanager_secret.db.arn
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.this.id
}
