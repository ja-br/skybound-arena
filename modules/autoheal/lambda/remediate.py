"""Auto-heal remediation: force a fresh ECS deployment to recycle degraded tasks.

Triggered by EventBridge when a heal-trigger alarm goes to ALARM. `force new
deployment` reuses the current task definition, so ECS runs the configured
blue/green process (green stands up, traffic shifts, bake, drain) with brand-new
tasks — clearing memory creep / stuck workers that health checks didn't kill.

It does NOT fix a bad image (that's what the compute deploy-rollback alarm +
circuit breaker are for). CLUSTER / SERVICE come from the Terraform-set env vars.

Cooldown guard: EventBridge fires on every OK→ALARM transition, so a *flapping*
alarm would otherwise force a redeploy on each edge and never let the service
settle. Before healing, this checks the service's own deployment state (no external
store needed):
  1. If a deployment is already rolling out, skip — one is already fixing things.
  2. If the last deployment started within HEAL_COOLDOWN_SECONDS, skip — give it
     time to take effect before piling on another.
Only when neither holds do we force a new deployment. Two alarms firing in the same
sub-second window could both pass the guard and each force a deploy (at worst one
redundant redeploy); the guard makes every subsequent edge a no-op once a deployment
is in flight. (A reserved-concurrency of 1 would serialize these, but this account's
concurrency limit forbids any reservation — see heal.tf.)
"""

import logging
import os
import time

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

ecs = boto3.client("ecs")

CLUSTER = os.environ["CLUSTER"]
SERVICE = os.environ["SERVICE"]
COOLDOWN_SECONDS = int(os.environ.get("HEAL_COOLDOWN_SECONDS", "300"))


def handler(event, _context):
    alarm = event.get("detail", {}).get("alarmName", "<unknown>")

    # Read the service's current deployment state — it doubles as our cooldown clock.
    svc = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])["services"][0]
    deployments = svc.get("deployments", [])

    # Guard 1: a deployment is already in flight — let it finish.
    in_progress = [d for d in deployments if d.get("rolloutState") == "IN_PROGRESS"]
    if in_progress:
        log.info(
            "Heal skipped (alarm '%s'): deployment %s already in progress.",
            alarm, in_progress[0]["id"],
        )
        return {"alarm": alarm, "action": "skipped", "reason": "deployment_in_progress"}

    # Guard 2: the last deployment started too recently — within the cooldown window.
    primary = next((d for d in deployments if d.get("status") == "PRIMARY"), None)
    if primary is not None:
        age = time.time() - primary["createdAt"].timestamp()
        if age < COOLDOWN_SECONDS:
            log.info(
                "Heal skipped (alarm '%s'): last deployment was %ds ago (< %ds cooldown).",
                alarm, int(age), COOLDOWN_SECONDS,
            )
            return {"alarm": alarm, "action": "skipped", "reason": "within_cooldown"}

    # Neither guard tripped — recycle the tasks.
    log.info("Heal triggered by alarm '%s' — forcing new deployment of %s/%s", alarm, CLUSTER, SERVICE)
    resp = ecs.update_service(cluster=CLUSTER, service=SERVICE, forceNewDeployment=True)

    new_deployments = resp.get("service", {}).get("deployments", [])
    new_primary = next((d for d in new_deployments if d.get("status") == "PRIMARY"), None)
    deployment_id = new_primary["id"] if new_primary else "<none>"
    log.info("Started deployment %s", deployment_id)

    return {"alarm": alarm, "action": "healed", "deployment_id": deployment_id}
