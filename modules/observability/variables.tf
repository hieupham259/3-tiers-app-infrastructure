variable "environment" {
  type        = string
  description = "Environment name"
}

variable "ecs_cluster_name" {
  type        = string
  description = "ECS cluster name to monitor"
}

variable "ecs_service_name" {
  type        = string
  description = "ECS service name to monitor"
}

variable "rds_instance_id" {
  type        = string
  description = "RDS instance identifier"
}

variable "alb_arn_suffix" {
  type        = string
  description = "ALB ARN suffix (for CW metric dimensions)"
}

variable "alarm_sns_topic_arn" {
  type        = string
  default     = null
  description = "SNS topic to send alerts to (Slack via Lambda, or email)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
