environment = "development"
region      = "us-east-1"

# --- Network ---
# Case 1 (empty account - self-create the VPC):
vpc_cidr = "10.10.0.0/16"
# existing_vpc_id = null  (default)

# Case 2 (BYO VPC from the platform team) - uncomment when needed:
# existing_vpc_id             = "vpc-0abc123def456"
# existing_private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
# existing_public_subnet_ids  = ["subnet-ddd", "subnet-eee", "subnet-fff"]

# --- RDS (development: small instance, single-AZ, short retention) ---
rds_instance_class        = "db.t4g.small"
rds_multi_az              = false
rds_storage_gb            = 20
rds_backup_retention_days = 7
rds_deletion_protection   = false

# --- ECS (development: 1 task, small CPU/memory) ---
ecs_task_cpu      = 512
ecs_task_memory   = 1024
ecs_desired_count = 1

# --- Domain (uncomment once Route53 + ACM are ready) ---
# domain_name          = "development.myapp.example.com"
# alb_acm_cert_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/<id>"
# frontend_cf_cert_arn = "arn:aws:acm:us-east-1:111111111111:certificate/<id>"
# hosted_zone_id       = "Z01234567890ABCDEFGH"

# --- Observability ---
# Set to an SNS topic ARN once an on-call channel is wired up. Leave commented
# to skip alarm actions (alarms still fire and are visible in CloudWatch).
# alarm_sns_topic_arn = "arn:aws:sns:us-east-1:111111111111:ops-alerts"

# --- Tags ---
tags = {
  Owner      = "platform-team@myorg.com"
  CostCenter = "CC-12345"
}
