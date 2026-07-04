# Target-tracking autoscaling for the ECS service.
#
# Scales on ECS service CPU (AWS/ECS CPUUtilization, dimensioned ClusterName/
# ServiceName) — the only load signal that is STABLE across a blue/green shift:
#   - ALBRequestCountPerTarget binds to a target-group resource label, which ECS
#     native blue/green swaps on every deploy (AWS documents it as unsupported for
#     the blue/green deployment type). It would go blind after the first shift.
#   - MatchmakingQueueDepth is in-memory + per-task + sampled only on a queue call —
#     a bursty, misleading aggregate. The documented path once matchmaking leaves
#     the process; the wrong foundation while it's a per-process deque.
# CPU is cluster/service-scoped, exactly like the no-running-tasks heal alarm, so it
# survives every shift. Terraform hands desired_count to the autoscaler and stops
# tracking it (see ignore_changes on the service in main.tf) so the two don't fight.

resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
  # role_arn omitted on purpose: Application Auto Scaling creates and uses its
  # service-linked role (AWSServiceRoleForApplicationAutoScaling_ECSService) on the
  # first RegisterScalableTarget. The applying principal needs iam:CreateServiceLinkedRole.
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
}
