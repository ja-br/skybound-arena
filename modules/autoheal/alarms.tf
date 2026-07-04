# Operational alarms. 
# treat_missing_data is set EXPLICITLY on every alarm, the default (`missing`) is
# wrong in different directions here: a ratio metric that divides by zero at idle
# would self-alarm under `breaching`, while an availability metric that stops
# publishing when the service dies would never fire under `missing`.
#
# All alarms notify SNS. Only unhealthy-hosts and no-running-tasks additionally
# feed the heal loop (heal.tf) runtime-degradation signals, not deploy-time
# signals. Error-rate is notify-only so it can't race the compute deploy-rollback.

# 1. App 5xx error rate (%) metric math over custom EMF counts. NOTIFY ONLY.
#    At idle requests=0 → x/0 → no datapoint → notBreaching (never breaching, or an
#    idle service would alarm on itself).
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name        = "${local.name}-high-error-rate"
  alarm_description = "App 5xx error rate above ${var.error_rate_threshold}% (notify only)."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "100 * FILL(errors, 0) / requests"
    label       = "error rate %"
    return_data = true
  }
  metric_query {
    id          = "errors"
    return_data = false
    metric {
      namespace   = var.metrics_namespace
      metric_name = "HttpErrorCount"
      dimensions  = local.game_dims
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id          = "requests"
    return_data = false
    metric {
      namespace   = var.metrics_namespace
      metric_name = "RequestCount"
      dimensions  = local.game_dims
      period      = 60
      stat        = "Sum"
    }
  }

  tags = { Name = "${local.name}-high-error-rate" }
}

# 2. Matchmaking latency p99 — the player-facing SLO. NOTIFY ONLY.
resource "aws_cloudwatch_metric_alarm" "high_matchmaking_latency" {
  alarm_name        = "${local.name}-high-matchmaking-latency"
  alarm_description = "Matchmaking p99 latency above ${var.matchmaking_latency_threshold_ms}ms (notify only)."

  namespace          = var.metrics_namespace
  metric_name        = "MatchmakingLatencyMs"
  dimensions         = local.game_dims
  extended_statistic = "p99"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.matchmaking_latency_threshold_ms
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-high-matchmaking-latency" }
}

# 3. ECS CPU high — capacity pressure. NOTIFY ONLY (the future autoscaling hook).
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name        = "${local.name}-ecs-cpu-high"
  alarm_description = "ECS service CPU utilization above ${var.cpu_high_threshold}% (notify only)."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions  = local.ecs_dims
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_high_threshold
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-ecs-cpu-high" }
}

# 4. Unhealthy hosts — a task is registered but failing health checks. HEAL TRIGGER.
#    UnHealthyHostCount is published per (LoadBalancer, TargetGroup) pair and needs
#    BOTH dimensions to resolve. ECS native blue/green moves production between the
#    blue and green target groups on every deploy and leaves it there, so a single
#    fixed TargetGroup dimension goes blind the moment traffic shifts to the other
#    group. Alarm on MAX(blue, green) instead: the idle group publishes no data (or
#    zero) and the production group is always covered, whichever color holds it. The
#    drained group's absent datapoints are filled to 0 so MAX reflects only the live
#    group. Minimum stat per group = unhealthy across every AZ node in that group.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name        = "${local.name}-unhealthy-hosts"
  alarm_description = "At least one production target failing health checks (either blue or green target group) — recycles tasks."

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "MAX([FILL(blue, 0), FILL(green, 0)])"
    label       = "unhealthy hosts (max of blue/green)"
    return_data = true
  }
  metric_query {
    id          = "blue"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = var.blue_target_group_arn_suffix
      }
      period = 60
      stat   = "Minimum"
    }
  }
  metric_query {
    id          = "green"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "UnHealthyHostCount"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = var.green_target_group_arn_suffix
      }
      period = 60
      stat   = "Minimum"
    }
  }

  tags = { Name = "${local.name}-unhealthy-hosts" }
}

# 5. No running tasks — the service is fully down. HEAL TRIGGER.
#    Container Insights STOPS emitting RunningTaskCount at zero tasks, so the alarm
#    must treat missing data as `breaching` or it would never fire when down. This
#    also reads ALARM during the Container-Insights cold-start lag on a fresh apply
#    (one spurious heal on first bring-up) — padded with datapoints_to_alarm.
resource "aws_cloudwatch_metric_alarm" "no_running_tasks" {
  alarm_name        = "${local.name}-no-running-tasks"
  alarm_description = "ECS running task count fell below 1 — service down, forces a redeploy."

  namespace   = "ECS/ContainerInsights"
  metric_name = "RunningTaskCount"
  dimensions  = local.ecs_dims
  statistic   = "Maximum"

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-no-running-tasks" }
}
