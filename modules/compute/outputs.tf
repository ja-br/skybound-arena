# Most of these are consumed by the pipeline module: CodeBuild pushes
# to the ECR repo, and the CodeDeploy deployment group targets the cluster,
# service, both target groups, and the production listener.

output "ecr_repository_url" {
  description = "ECR repo URL. Buildspec tags images here with the git SHA."
  value       = aws_ecr_repository.app.repository_url
}

output "cluster_name" {
  description = "ECS cluster name (CodeDeploy deployment group target)."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name (CodeDeploy deployment group target)."
  value       = aws_ecs_service.app.name
}

output "blue_target_group_name" {
  description = "Blue target group name (CodeDeploy load balancer info)."
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Green target group name (CodeDeploy load balancer info)."
  value       = aws_lb_target_group.green.name
}

output "prod_listener_arn" {
  description = "Production listener ARN CodeDeploy shifts traffic on."
  value       = aws_lb_listener.prod.arn
}

output "task_execution_role_arn" {
  description = "Task execution role ARN. Fills <EXECUTION_ROLE_ARN> in taskdef.json."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Task role ARN. Fills <TASK_ROLE_ARN> in taskdef.json."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "App log group. Fills <LOG_GROUP> in taskdef.json."
  value       = aws_cloudwatch_log_group.app.name
}

output "alb_dns_name" {
  description = "Public ALB hostname — curl /healthz and /version here."
  value       = aws_lb.this.dns_name
}
