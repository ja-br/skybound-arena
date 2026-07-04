output "sns_topic_arn" {
  description = "Alerts topic — subscribe more endpoints (Discord/chatbot) here later."
  value       = aws_sns_topic.alerts.arn
}

output "remediate_lambda_name" {
  description = "Remediation Lambda (tail its logs to see heal actions)."
  value       = aws_lambda_function.remediate.function_name
}

output "heal_alarm_names" {
  description = "Alarms that trigger auto-heal (force-new-deployment)."
  value = [
    aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.no_running_tasks.alarm_name,
  ]
}

output "alarm_names" {
  description = "All operational alarms created by this module."
  value = [
    aws_cloudwatch_metric_alarm.high_error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.high_matchmaking_latency.alarm_name,
    aws_cloudwatch_metric_alarm.ecs_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.no_running_tasks.alarm_name,
  ]
}
