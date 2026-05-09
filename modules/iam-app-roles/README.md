# Module: iam-app-roles

IAM roles for the ECS task: task execution role + task role.

## Roles

| Role | Purpose | Permissions |
|------|---------|-------------|
| `task_exec` | Used by the ECS agent (pull image, fetch secrets, write logs) | AmazonECSTaskExecutionRolePolicy + secretsmanager:GetSecretValue for RDS |
| `task` | Used by app code at runtime | ssm:Get* for `/3-tiers-app/<env>/*` |

## BYO

Both roles support BYO via `existing_task_exec_role_arn` / `existing_task_role_arn`.
