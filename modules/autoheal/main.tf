# Autoheal module: the live-ops reaction stack — detect (alarms) → notify (SNS) →
# heal (EventBridge → Lambda force-new-deployment). The observability module is
# "see"; this module is "react".
#
# Alarm homes are split on purpose: the deploy-rollback alarm lives in `compute`
# (the service must name it in its own alarms{} block — housing it here would make
# compute depend on autoheal which depends on compute, a cycle). This module owns
# the *operational* alarms and the heal loop.

locals {
  name = "${var.env}-skybound"

  # Reused metric dimension tails.
  game_dims = { service = var.metrics_service, env = var.env }
  ecs_dims  = { ClusterName = var.cluster_name, ServiceName = var.service_name }

  service_arn = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${var.cluster_name}/${var.service_name}"
}

data "aws_caller_identity" "current" {}
