resource "aws_db_subnet_group" "this" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.environment}-rds-subnet-group" })
}

resource "aws_security_group" "this" {
  name        = "${var.environment}-rds-sg"
  description = "RDS PostgreSQL security group - ingress only from ECS"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.environment}-rds-sg" })
}

resource "aws_security_group_rule" "ingress_from_ecs" {
  count                    = length(var.ingress_security_group_ids)
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.ingress_security_group_ids[count.index]
  security_group_id        = aws_security_group.this.id
}

resource "random_password" "master" {
  length  = 32
  special = true
  # Characters disallowed by RDS in passwords are excluded
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "/3-tiers-app/${var.environment}/rds/master"
  description             = "RDS master credentials for ${var.environment}"
  recovery_window_in_days = 7
  tags                    = var.tags

  lifecycle {
    # Prevent accidental destroy: deleting this secret strands the RDS master credentials and breaks every running ECS task until the secret is rotated and re-injected.
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    dbname   = var.db_name
    port     = 5432
  })
}

resource "aws_db_instance" "this" {
  identifier = "${var.environment}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.existing_kms_key_arn

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result

  multi_az = var.multi_az

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_days
  backup_window           = "16:00-17:00" # UTC = 23:00 ICT
  maintenance_window      = "sun:18:00-sun:19:00"

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.environment}-postgres-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  apply_immediately = false

  tags = merge(var.tags, { Name = "${var.environment}-postgres" })

  lifecycle {
    # Prevent accidental destroy: this is the primary application database; recovery requires a snapshot restore and incurs full app downtime.
    prevent_destroy = true
    ignore_changes  = [final_snapshot_identifier, password]
  }
}
