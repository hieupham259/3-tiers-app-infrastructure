locals {
  create_exec_role = var.existing_task_exec_role_arn == null
  create_task_role = var.existing_task_role_arn == null
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- Task execution role (ECR pull, secrets, log push) ---
resource "aws_iam_role" "task_exec" {
  count              = local.create_exec_role ? 1 : 0
  name               = "3-tiers-app-${var.environment}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  count      = local.create_exec_role ? 1 : 0
  role       = aws_iam_role.task_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_exec_secrets" {
  count = local.create_exec_role ? 1 : 0
  name  = "secrets-read"
  role  = aws_iam_role.task_exec[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.rds_secret_arn
      }
    ]
  })
}

# --- Task role (used by app code for AWS APIs) ---
resource "aws_iam_role" "task" {
  count              = local.create_task_role ? 1 : 0
  name               = "3-tiers-app-${var.environment}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "task_inline" {
  count = local.create_task_role ? 1 : 0
  name  = "app-runtime"
  role  = aws_iam_role.task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/3-tiers-app/${var.environment}/*"
      }
    ]
  })
}
