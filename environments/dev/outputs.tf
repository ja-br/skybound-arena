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
  description = "ECS cluster (CodeDeploy target)."
}

output "ecs_service_name" {
  value       = module.compute.service_name
  description = "ECS service (CodeDeploy target)."
}

# taskdef.json placeholder fills — the buildspec renders these into the artifact.
output "task_execution_role_arn" {
  value       = module.compute.task_execution_role_arn
  description = "Fills <EXECUTION_ROLE_ARN> in taskdef.json."
}

output "task_role_arn" {
  value       = module.compute.task_role_arn
  description = "Fills <TASK_ROLE_ARN> in taskdef.json."
}

output "log_group_name" {
  value       = module.compute.log_group_name
  description = "Fills <LOG_GROUP> in taskdef.json."
}
