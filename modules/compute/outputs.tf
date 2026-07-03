# Consumed by the (future) app pipeline: CodeBuild pushes to the ECR repo, and
# the deploy stage updates the ECS service (cluster + service name) to register a
# new task definition, which ECS rolls out via its native blue/green strategy.

output "ecr_repository_url" {
  description = "ECR repo URL. Buildspec tags images here with the git SHA."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repo ARN. Scopes the pipeline's image-push permissions."
  value       = aws_ecr_repository.app.arn
}

output "cluster_name" {
  description = "ECS cluster name (the app pipeline's deploy target)."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name (the app pipeline updates it to deploy)."
  value       = aws_ecs_service.app.name
}

output "blue_target_group_name" {
  description = "Blue (initial production) target group name."
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Green (alternate) target group name ECS shifts traffic to."
  value       = aws_lb_target_group.green.name
}

output "prod_listener_arn" {
  description = "Production listener ARN (its rule is what ECS repoints on a shift)."
  value       = aws_lb_listener.prod.arn
}

output "task_execution_role_arn" {
  description = "Task execution role ARN (the pipeline deploy role passes it on register-task-definition)."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Task role ARN (the pipeline deploy role passes it on register-task-definition)."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "App log group name."
  value       = aws_cloudwatch_log_group.app.name
}

output "alb_dns_name" {
  description = "Public ALB hostname — curl /healthz and /version here."
  value       = aws_lb.this.dns_name
}

# --- Observability inputs ----------------------------------------------------
# CloudWatch dimensions the dashboard keys off. ALB/target-group metrics are
# dimensioned by arn_suffix, not name or ARN.

output "alb_arn_suffix" {
  description = "ALB ARN suffix — the CloudWatch LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "blue_target_group_arn_suffix" {
  description = "Blue target-group ARN suffix (TargetGroup dimension). Not consumed yet; ALB widgets use the LoadBalancer dimension, stable across a blue/green shift."
  value       = aws_lb_target_group.blue.arn_suffix
}

output "green_target_group_arn_suffix" {
  description = "Green target-group ARN suffix (TargetGroup dimension). Not consumed yet."
  value       = aws_lb_target_group.green.arn_suffix
}

output "metrics_namespace" {
  description = "EMF namespace injected into the container — the dashboard reads it here so app + dashboard can't drift."
  value       = var.metrics_namespace
}

output "metrics_service" {
  description = "The `service` dimension value (the container name) the app tags metrics with."
  value       = var.container_name
}
