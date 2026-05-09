# Module: ecs-cluster

ECS Fargate cluster + capacity providers + Container Insights.

## Features

- Capacity providers: FARGATE + FARGATE_SPOT (Spot saves cost for non-critical workloads)
- Container Insights enabled by default (CloudWatch metrics + logs)

## Usage

```hcl
module "ecs_cluster" {
  source      = "../../modules/ecs-cluster"
  environment = var.environment
}
```
