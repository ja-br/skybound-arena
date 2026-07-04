variable "env" {
  description = "Environment name (dev/staging/prod). Prefixes resource names."
  type        = string
}

variable "region" {
  description = "AWS region (used to construct the ECS service ARN for IAM scoping)."
  type        = string
}

# --- From the compute module -------------------------------------------------
variable "cluster_name" {
  description = "ECS cluster name (heal target + ClusterName metric dimension)."
  type        = string
}

variable "service_name" {
  description = "ECS service name (heal target + ServiceName metric dimension)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (LoadBalancer dimension — required alongside TargetGroup for UnHealthyHostCount)."
  type        = string
}

variable "blue_target_group_arn_suffix" {
  description = "Blue target-group ARN suffix. UnHealthyHostCount is alarmed as a MAX over both target groups, since ECS blue/green moves production between them."
  type        = string
}

variable "green_target_group_arn_suffix" {
  description = "Green target-group ARN suffix. Paired with blue so the unhealthy-hosts alarm follows production across a blue/green shift."
  type        = string
}

variable "metrics_namespace" {
  description = "EMF namespace the app publishes custom metrics under (from compute so it can't drift)."
  type        = string
}

variable "metrics_service" {
  description = "The `service` dimension value the app tags custom metrics with (the container name)."
  type        = string
}

# --- Notification ------------------------------------------------------------
variable "notification_email" {
  description = "Email subscribed to the alerts SNS topic. Empty = topic only, no subscription."
  type        = string
  default     = ""
}

# --- Alarm thresholds (defaulted; tune per environment) ----------------------
variable "error_rate_threshold" {
  description = "App 5xx error-rate percentage that alarms (notify only)."
  type        = number
  default     = 5
}

variable "matchmaking_latency_threshold_ms" {
  description = "Matchmaking p99 latency (ms) that alarms (notify only)."
  type        = number
  default     = 2000
}

variable "cpu_high_threshold" {
  description = "ECS service CPU utilization percentage that alarms (notify only)."
  type        = number
  default     = 80
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the remediation Lambda."
  type        = number
  default     = 14
}
