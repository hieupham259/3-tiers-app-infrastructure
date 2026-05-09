resource "aws_ecs_cluster" "this" {
  name = "${var.environment}-3-tiers-app"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, { Name = "${var.environment}-3-tiers-app" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = var.capacity_providers

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.default_capacity_provider
  }
}
