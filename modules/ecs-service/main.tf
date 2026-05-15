locals {
  family = "${var.environment}-${var.service_name}"
}

# --- Security group for task ENI ---
resource "aws_security_group" "task" {
  name        = "${local.family}-sg"
  description = "ECS task ENI security group - ingress only from ALB"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.family}-sg" })
}

resource "aws_security_group_rule" "ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  security_group_id        = aws_security_group.task.id
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.task.id
}

# --- CloudWatch log group ---
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.family}"
  retention_in_days = 30
  tags              = var.tags
}

# --- Task definition ---
resource "aws_ecs_task_definition" "this" {
  family                   = local.family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.existing_task_exec_role_arn
  task_role_arn            = var.existing_task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      environment = [
        { name = "NODE_ENV", value = var.environment },
        { name = "DB_HOST", value = var.rds_endpoint }
      ]
      secrets = [
        { name = "DB_CREDENTIALS", valueFrom = var.rds_secret_arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = var.tags

  lifecycle {
    # The app repo registers a new task definition with the image SHA - ignore image diffs
    ignore_changes = [container_definitions]
  }
}

data "aws_region" "current" {}

# --- Service ---
resource "aws_ecs_service" "this" {
  name            = local.family
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags

  lifecycle {
    # The app deploy pipeline updates task_definition - ignore
    ignore_changes = [task_definition, desired_count]
  }
}
