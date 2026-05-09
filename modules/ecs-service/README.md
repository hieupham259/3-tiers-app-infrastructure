# Module: ecs-service

ECS Fargate task definition + service + security group + CloudWatch log group.

## Key behaviors

- `lifecycle.ignore_changes = [container_definitions]` on the task def lets the app deploy pipeline register a new task def with the image SHA without Terraform reverting it.
- `lifecycle.ignore_changes = [task_definition, desired_count]` on the service prevents Terraform from overwriting autoscaling and app deploys.
- Deployment circuit breaker auto-rolls back when a task fails its health check.
- Container health check: `curl http://localhost:<port>/health`.

## Usage

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  environment           = var.environment
  cluster_name          = module.ecs_cluster.cluster_name
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.security_group_id
  ecr_repository_url    = module.ecr_backend.repository_url
  rds_endpoint          = module.rds.endpoint
  rds_secret_arn        = module.rds.secret_arn

  task_cpu      = var.ecs_task_cpu
  task_memory   = var.ecs_task_memory
  desired_count = var.ecs_desired_count
}
```

> Remember to append `module.ecs_service.security_group_id` to `module.rds.ingress_security_group_ids`.
