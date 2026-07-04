# Values the pipeline and the bootstrap step consume.

output "ecr_repository_url" {
  description = "Push the bootstrap image here; the pipeline pushes SHA-tagged images here."
  value       = module.compute.ecr_repository_url
}

output "alb_dns_name" {
  description = "Public ALB hostname — curl /healthz and /version here after deploy."
  value       = module.compute.alb_dns_name
}

output "ecs_cluster_name" {
  value       = module.compute.cluster_name
  description = "ECS cluster (the app pipeline's deploy target)."
}

output "ecs_service_name" {
  value       = module.compute.service_name
  description = "ECS service (the app pipeline updates it to deploy)."
}

# Passed into the pipeline module for the deploy stage (PassRole + logging).
output "task_execution_role_arn" {
  value       = module.compute.task_execution_role_arn
  description = "Task execution role ARN (deploy stage passes it on register-task-definition)."
}

output "task_role_arn" {
  value       = module.compute.task_role_arn
  description = "Task role ARN (deploy stage passes it on register-task-definition)."
}

output "log_group_name" {
  value       = module.compute.log_group_name
  description = "App log group name."
}

output "dashboard_url" {
  value       = module.observability.dashboard_url
  description = "CloudWatch live-ops dashboard (the demo/README screenshot)."
}

output "sns_topic_arn" {
  value       = module.autoheal.sns_topic_arn
  description = "Alerts SNS topic (subscribe more endpoints here)."
}

output "remediate_lambda_name" {
  value       = module.autoheal.remediate_lambda_name
  description = "Auto-heal remediation Lambda (tail its logs to see heal actions)."
}
