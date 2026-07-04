# Deploy-rollback alarm: the metric-alarm half of the blue/green safety net.
#
# The circuit breaker catches a deploy that can't pass health checks. This catches
# the subtler failure: green goes healthy, takes traffic, and *then* spikes 5xx.
# It's referenced by the service's top-level `alarms{}` block (main.tf), so ECS
# rolls the deployment back to blue when it fires during a shift.
#
# Scoped tightly to a deploy-failure signal (a 5xx burst) and kept affirmatively in
# OK at steady state (treat_missing_data = notBreaching) an alarm stuck in
# INSUFFICIENT_DATA can interfere with how ECS evaluates the deployment.

resource "aws_cloudwatch_metric_alarm" "deploy_5xx" {
  alarm_name        = "${local.name}-deploy-5xx"
  alarm_description = "Target 5xx burst — trips blue/green rollback during a deployment."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  dimensions  = { LoadBalancer = aws_lb.this.arn_suffix }

  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.deploy_alarm_5xx_threshold
  period              = var.deploy_alarm_period
  evaluation_periods  = var.deploy_alarm_eval_periods
  treat_missing_data  = "notBreaching"

  tags = { Name = "${local.name}-deploy-5xx" }
}
