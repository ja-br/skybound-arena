# Live-ops dashboard: the single pane the streamer-spike demo is watched on.
# Three rows — game signals (custom EMF), edge/HTTP (ALB), capacity (ECS).

locals {
  name = "${var.env}-skybound-overview"
  ns   = var.metrics_namespace
  svc  = var.metrics_service

  # Reused dimension tails so the metric arrays stay readable.
  game_dims = ["service", var.metrics_service, "env", var.env]
  ecs_dims  = ["ClusterName", var.cluster_name, "ServiceName", var.service_name]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      # --- Row 1: game signals (custom EMF metrics) -------------------------
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Matchmaking latency p99 (ms)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            concat([local.ns, "MatchmakingLatencyMs"], local.game_dims, [{ stat = "p99" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Matchmaking queue depth"
          region = var.region
          view   = "timeSeries"
          metrics = [
            concat([local.ns, "MatchmakingQueueDepth"], local.game_dims, [{ stat = "Average", label = "avg" }]),
            concat([local.ns, "MatchmakingQueueDepth"], local.game_dims, [{ stat = "Maximum", label = "max" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Matches made & players created"
          region = var.region
          view   = "timeSeries"
          metrics = [
            concat([local.ns, "MatchesMade"], local.game_dims, [{ stat = "Sum" }]),
            concat([local.ns, "PlayersCreated"], local.game_dims, [{ stat = "Sum" }]),
          ]
        }
      },

      # --- Row 2: HTTP / edge (app error rate + ALB) ------------------------
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "App error rate (%)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            [{ expression = "100 * FILL(errors, 0) / requests", label = "error rate %", id = "e1" }],
            concat([local.ns, "HttpErrorCount"], local.game_dims, [{ id = "errors", stat = "Sum", visible = false }]),
            concat([local.ns, "RequestCount"], local.game_dims, [{ id = "requests", stat = "Sum", visible = false }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "ALB requests & target 5xx"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "requests" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "target 5xx" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "ALB target response time p99 (s)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99" }],
          ]
        }
      },

      # --- Row 3: capacity (ECS) --------------------------------------------
      # CPU/memory % live in AWS/ECS; RunningTaskCount lives in the separate
      # ECS/ContainerInsights namespace (Container Insights is enabled).
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU & memory utilization (%)"
          region = var.region
          view   = "timeSeries"
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_dims, [{ stat = "Average", label = "CPU %" }]),
            concat(["AWS/ECS", "MemoryUtilization"], local.ecs_dims, [{ stat = "Average", label = "Mem %" }]),
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "ECS running task count"
          region = var.region
          view   = "timeSeries"
          metrics = [
            concat(["ECS/ContainerInsights", "RunningTaskCount"], local.ecs_dims, [{ stat = "Average" }]),
          ]
        }
      },
    ]
  })
}
