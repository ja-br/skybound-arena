output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "App-task security group ID (ALB-only ingress)"
  value       = aws_security_group.app.id
}
