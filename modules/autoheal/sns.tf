# Alerts topic. Every alarm publishes here; a human sees it. The heal loop
# (heal.tf) is a separate path off the same alarms, so notification and remediation
# are independent.

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = { Name = "${local.name}-alerts" }
}

# Email subscription is optional: an empty notification_email creates the topic
# with no subscription (subscribe by hand later). Email subs require the recipient
# to click a confirmation link before they deliver.
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
