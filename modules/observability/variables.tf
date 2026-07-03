variable "env" {
  description = "Environment name (dev/staging/prod). Also the `env` metric dimension value."
  type        = string
}

variable "region" {
  description = "AWS region the dashboard renders metrics from."
  type        = string
}

# --- From the compute module -------------------------------------------------
variable "cluster_name" {
  description = "ECS cluster name (ClusterName dimension for ECS metrics)."
  type        = string
}

variable "service_name" {
  description = "ECS service name (ServiceName dimension for ECS metrics)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (LoadBalancer dimension for ALB metrics)."
  type        = string
}

variable "metrics_namespace" {
  description = "EMF namespace the app publishes custom metrics under. Comes from compute so it can't drift from what the container emits."
  type        = string
}

variable "metrics_service" {
  description = "The `service` dimension value the app tags custom metrics with (the container name)."
  type        = string
}
