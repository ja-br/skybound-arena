"""Auto-heal remediation: force a fresh ECS deployment to recycle degraded tasks.

Triggered by EventBridge when a heal-trigger alarm goes to ALARM. `force new
deployment` reuses the current task definition, so ECS runs the configured
blue/green process (green stands up, traffic shifts, bake, drain) with brand-new
tasks — clearing memory creep / stuck workers that health checks didn't kill.

It does NOT fix a bad image (that's what the compute deploy-rollback alarm +
circuit breaker are for). CLUSTER / SERVICE come from the Terraform-set env vars.
"""

import logging
import os

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

ecs = boto3.client("ecs")

CLUSTER = os.environ["CLUSTER"]
SERVICE = os.environ["SERVICE"]


def handler(event, _context):
    alarm = event.get("detail", {}).get("alarmName", "<unknown>")
    log.info("Heal triggered by alarm '%s' — forcing new deployment of %s/%s", alarm, CLUSTER, SERVICE)

    resp = ecs.update_service(cluster=CLUSTER, service=SERVICE, forceNewDeployment=True)

    # The update response carries the new deployment; no separate Describe needed.
    deployments = resp.get("service", {}).get("deployments", [])
    deployment_id = deployments[0]["id"] if deployments else "<none>"
    log.info("Started deployment %s", deployment_id)

    return {"alarm": alarm, "deployment_id": deployment_id}
