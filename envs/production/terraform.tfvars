environment = "production"
region      = "us-east-1"

# --- Network ---
vpc_cidr = "10.20.0.0/16"
# existing_vpc_id             = "vpc-0xxx..."
# existing_private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
# existing_public_subnet_ids  = ["subnet-ddd", "subnet-eee", "subnet-fff"]

# --- RDS (production: large instance, Multi-AZ, long retention) ---
rds_instance_class        = "db.r6g.large"
rds_multi_az              = true
rds_storage_gb            = 100
rds_backup_retention_days = 30
rds_deletion_protection   = true

# --- ECS (production: larger scale) ---
ecs_task_cpu      = 2048
ecs_task_memory   = 4096
ecs_desired_count = 3

# --- Domain (uncomment once Route53 + ACM are ready) ---
# domain_name          = "myapp.example.com"
# alb_acm_cert_arn     = "arn:aws:acm:us-east-1:222222222222:certificate/<id>"
# frontend_cf_cert_arn = "arn:aws:acm:us-east-1:222222222222:certificate/<id>"
# hosted_zone_id       = "Z01234567890ABCDEFGH"

# --- Observability ---
# Set to an SNS topic ARN once an on-call channel is wired up. Leave commented
# to skip alarm actions (alarms still fire and are visible in CloudWatch).
# alarm_sns_topic_arn = "arn:aws:sns:us-east-1:222222222222:ops-alerts"

# --- Tags ---
tags = {
  Owner      = "platform-team@myorg.com"
  CostCenter = "CC-12345"
}
