# Module: observability

CloudWatch metric alarms for ECS, RDS, ALB. Skeleton - extend over time with
dashboards, log metric filters, X-Ray, depending on project scope.

## Alarms

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| `ecs-cpu-high` | `AWS/ECS CPUUtilization` | > 80% over 3 minutes |
| `rds-connections-high` | `AWS/RDS DatabaseConnections` | > 80 over 3 minutes |
| `alb-5xx` | `AWS/ApplicationELB HTTPCode_Target_5XX_Count` | > 10/min |

All alarms send their action to `var.alarm_sns_topic_arn` (Slack via Lambda forwarder, or email subscription).
