# Load test — k6 spike

A [k6](https://k6.io) script that drives real traffic at the **dev** ALB so the ECS
service crosses its CPU scale-out target and the autoscaler adds tasks. It's the
organic counterpart to the Slice-2 alarm tests: real load, real metrics, real
scaling — no `set-alarm-state`.

This is a **local tool**. It is not deployed, ships in no image, and changes no
infrastructure. It hits the already-public dev ALB on port 80.

## The problem this solves

The service had static capacity and every reaction path had only ever been tested
with forced alarm state. This test proves the real thing end to end: traffic → CPU
climbs → target-tracking autoscaler adds tasks → traffic stops → tasks scale back in.
Along the way the Slice-2 alarms finally see real data.

## Run it

Install k6 (`brew install k6`, or see the k6 docs), then from `environments/dev`
grab the ALB hostname and point k6 at it:

```bash
# from code/environments/dev
BASE_URL=http://$(terraform output -raw alb_dns_name) k6 run ../../app/load/spike.js
```

`BASE_URL` is required and read from the environment — nothing is hardcoded. The
default profile ramps to 80 VUs over ~9 minutes (warm up → hard ramp → sustain →
drain) so scale-out and scale-in are both observable.

## What to watch (in another terminal)

```bash
# Scaling activities — the autoscaler adding/removing tasks:
aws application-autoscaling describe-scaling-activities --service-namespace ecs \
  --resource-id service/dev-skybound-cluster/dev-skybound-api

# Desired vs running task count climbing, then falling:
aws ecs describe-services --cluster dev-skybound-cluster --services dev-skybound-api \
  --query 'services[0].{desired:desiredCount,running:runningCount}'
```

Also expect: the `dev-skybound-ecs-cpu-high` alarm may go ALARM (notify-only, pages
at 80% — scaling kicks in first at 60%), and the SNS email arrives. The payoff is
that `dev-skybound-unhealthy-hosts` and the latency alarms are now evaluating **real
metric data** for the first time.

## Guardrail — don't knock the tasks over

Keep the spike sized to **cross the 60% CPU scale-out target, not to fail health
checks.** If tasks saturate hard enough that `/healthz` starts failing, the Slice-2
`unhealthy_hosts` alarm trips and the heal Lambda forces a **full blue/green
redeploy** — which stands up a green task set (≈doubling the task footprint) *while
the autoscaler is still scaling out*, and there is no heal cooldown guard yet. On a
flapping spike that redeploy re-fires on every OK→ALARM edge.

The default profile is tuned for a clean autoscaling demo. If you *want* to watch the
heal loop and autoscaler interact, raise the peak VUs deliberately and know that's
what you're doing — it's opt-in churn, not a clean scaling signal.

## Notes

- **Matchmaking is in-memory per task.** With more than one running task, the two
  queue calls in an iteration can land on different tasks and both stay `QUEUED` — no
  match forms. That's expected; the goal is request volume to move CPU, not match
  formation. The script counts `matches_formed` for visibility but never asserts on it.
- **Not in CI.** Run on demand from a workstation. Wiring it into the pipeline as a
  gated stage is a later slice.
