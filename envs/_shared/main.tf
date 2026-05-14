locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = "3-tiers-app"
    ManagedBy   = "terraform"
  })
}

module "network" {
  source = "../../modules/network"

  environment                 = var.environment
  vpc_cidr                    = var.vpc_cidr
  existing_vpc_id             = var.existing_vpc_id
  existing_private_subnet_ids = var.existing_private_subnet_ids
  existing_public_subnet_ids  = var.existing_public_subnet_ids
  tags                        = local.common_tags
}

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "ecr_backend" {
#   source      = "../../modules/ecr"
#   environment = var.environment
#   repo_name   = "3-tiers-app-backend"
#   tags        = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "alb" {
#   source                = "../../modules/alb"
#   environment           = var.environment
#   vpc_id                = module.network.vpc_id
#   public_subnet_ids     = module.network.public_subnet_ids
#   domain_name           = var.domain_name
#   existing_acm_cert_arn = var.alb_acm_cert_arn
#   tags                  = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "ecs_cluster" {
#   source      = "../../modules/ecs-cluster"
#   environment = var.environment
#   tags        = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "rds" {
#   source            = "../../modules/rds"
#   environment       = var.environment
#   vpc_id            = module.network.vpc_id
#   subnet_ids        = module.network.private_subnet_ids
#   instance_class    = var.rds_instance_class
#   multi_az          = var.rds_multi_az
#   allocated_storage = var.rds_storage_gb
#
#   backup_retention_days = var.rds_backup_retention_days
#   deletion_protection   = var.rds_deletion_protection
#   skip_final_snapshot   = var.environment != "production"
#
#   ingress_security_group_ids = [module.ecs_service.security_group_id]
#
#   tags = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "iam_app_roles" {
#   source              = "../../modules/iam-app-roles"
#   environment         = var.environment
#   rds_secret_arn      = module.rds.secret_arn
#   frontend_bucket_arn = module.frontend_cdn.bucket_arn
#   tags                = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "ecs_service" {
#   source                = "../../modules/ecs-service"
#   environment           = var.environment
#   cluster_name          = module.ecs_cluster.cluster_name
#   vpc_id                = module.network.vpc_id
#   private_subnet_ids    = module.network.private_subnet_ids
#   alb_target_group_arn  = module.alb.target_group_arn
#   alb_security_group_id = module.alb.security_group_id
#   ecr_repository_url    = module.ecr_backend.repository_url
#
#   rds_endpoint   = module.rds.endpoint
#   rds_secret_arn = module.rds.secret_arn
#
#   task_cpu      = var.ecs_task_cpu
#   task_memory   = var.ecs_task_memory
#   desired_count = var.ecs_desired_count
#
#   existing_task_exec_role_arn = module.iam_app_roles.task_exec_role_arn
#   existing_task_role_arn      = module.iam_app_roles.task_role_arn
#
#   tags = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "frontend_cdn" {
#   source                  = "../../modules/frontend-cdn"
#   environment             = var.environment
#   domain_name             = var.domain_name
#   existing_acm_cert_arn   = var.frontend_cf_cert_arn
#   existing_hosted_zone_id = var.hosted_zone_id
#   tags                    = local.common_tags
# }

# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04
# module "observability" {
#   source              = "../../modules/observability"
#   environment         = var.environment
#   ecs_cluster_name    = module.ecs_cluster.cluster_name
#   ecs_service_name    = module.ecs_service.service_name
#   rds_instance_id     = module.rds.db_instance_id
#   alb_arn_suffix      = module.alb.alb_arn_suffix
#   alarm_sns_topic_arn = var.alarm_sns_topic_arn
#   tags                = local.common_tags
# }
