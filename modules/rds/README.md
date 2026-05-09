# Module: rds

RDS PostgreSQL + DB subnet group + security group + Secrets Manager.

## Features

- Multi-AZ optional (toggle via `var.multi_az` - production: `true`)
- Storage encryption is mandatory (KMS) + Performance Insights
- Master password is auto-generated and stored in Secrets Manager (`/3-tiers-app/<env>/rds/master`)
- Configurable automated backup retention (development: 7d / production: 30d)
- Deletion protection defaults to `true`
- BYO KMS key support (`existing_kms_key_arn`)

## Usage

```hcl
module "rds" {
  source            = "../../modules/rds"
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  instance_class    = var.rds_instance_class
  multi_az          = var.rds_multi_az
  allocated_storage = var.rds_storage_gb

  ingress_security_group_ids = [module.ecs_service.security_group_id]
}
```

## Backup retention

| Env | Retention | Rationale |
|-----|-----------|-----------|
| development | 7 days | Sufficient recovery window for debugging |
| production | 30 days | Compliance + disaster recovery |
