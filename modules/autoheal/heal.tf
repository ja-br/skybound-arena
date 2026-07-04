# The heal loop: EventBridge watches the two heal-trigger alarms transition to
# ALARM and invokes the remediation Lambda, which forces a fresh ECS deployment.
#
# EventBridge fires on a state *transition* (OK→ALARM), not continuously, so a stuck
# alarm heals once. A *flapping* alarm (OK↔ALARM) is the churn source — the Lambda's
# cooldown guard (see remediate.py) absorbs it by skipping a redeploy when one is
# already in progress or the last one was within var.heal_cooldown_seconds.

# --- Remediation Lambda ------------------------------------------------------
data "archive_file" "remediate" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate.py"
  output_path = "${path.module}/lambda/remediate.zip"
}

resource "aws_cloudwatch_log_group" "remediate" {
  name              = "/aws/lambda/${local.name}-remediate"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "remediate" {
  name               = "${local.name}-remediate"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# force-new-deployment reuses the current task def (registers nothing) → no
# iam:PassRole. DescribeServices is needed for the cooldown guard (read the service's
# current deployment state before deciding whether to redeploy).
data "aws_iam_policy_document" "remediate" {
  statement {
    sid       = "ForceNewDeployment"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [local.service_arn]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.remediate.arn}:*"]
  }
}

resource "aws_iam_role_policy" "remediate" {
  name   = "${local.name}-remediate"
  role   = aws_iam_role.remediate.id
  policy = data.aws_iam_policy_document.remediate.json
}

resource "aws_lambda_function" "remediate" {
  function_name    = "${local.name}-remediate"
  role             = aws_iam_role.remediate.arn
  runtime          = "python3.12"
  handler          = "remediate.handler"
  filename         = data.archive_file.remediate.output_path
  source_code_hash = data.archive_file.remediate.output_base64sha256
  timeout          = 30

  # No reserved_concurrent_executions: this account's total concurrency is 10 and AWS
  # forbids dropping unreserved below 10, so any reservation is rejected. The cooldown
  # guard in remediate.py is the real protection against racing redeploys; reserved=1
  # was only belt-and-suspenders. Residual risk: two heal alarms firing in the same
  # sub-second window could both pass the guard → at worst one redundant redeploy.

  environment {
    variables = {
      CLUSTER               = var.cluster_name
      SERVICE               = var.service_name
      HEAL_COOLDOWN_SECONDS = var.heal_cooldown_seconds
    }
  }

  depends_on = [aws_cloudwatch_log_group.remediate]
  tags       = { Name = "${local.name}-remediate" }
}

# --- EventBridge: heal-trigger alarms → Lambda -------------------------------
resource "aws_cloudwatch_event_rule" "heal" {
  name        = "${local.name}-heal"
  description = "Force an ECS redeploy when a heal-trigger alarm fires."

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [
        aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
        aws_cloudwatch_metric_alarm.no_running_tasks.alarm_name,
      ]
      state = { value = ["ALARM"] }
    }
  })

  tags = { Name = "${local.name}-heal" }
}

resource "aws_cloudwatch_event_target" "heal" {
  rule      = aws_cloudwatch_event_rule.heal.name
  target_id = "remediate-lambda"
  arn       = aws_lambda_function.remediate.arn
}

resource "aws_lambda_permission" "heal" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.heal.arn
}
