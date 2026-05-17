module "stack" {
  source = "../_shared"

  environment                 = var.environment
  region                      = var.region
  vpc_cidr                    = var.vpc_cidr
  existing_vpc_id             = var.existing_vpc_id
  existing_private_subnet_ids = var.existing_private_subnet_ids
  existing_public_subnet_ids  = var.existing_public_subnet_ids

  rds_instance_class        = var.rds_instance_class
  rds_multi_az              = var.rds_multi_az
  rds_storage_gb            = var.rds_storage_gb
  rds_backup_retention_days = var.rds_backup_retention_days
  rds_deletion_protection   = var.rds_deletion_protection

  ecs_task_cpu      = var.ecs_task_cpu
  ecs_task_memory   = var.ecs_task_memory
  ecs_desired_count = var.ecs_desired_count

  domain_name          = var.domain_name
  alb_acm_cert_arn     = var.alb_acm_cert_arn
  frontend_cf_cert_arn = var.frontend_cf_cert_arn
  hosted_zone_id       = var.hosted_zone_id

  alarm_sns_topic_arn = var.alarm_sns_topic_arn

  repository = var.repository
  tags       = var.tags
}
