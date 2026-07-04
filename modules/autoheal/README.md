# Autoheal — alarms, notification & self-healing

The reaction half of live-ops. The observability module lets you *see* the service;
this module lets the service *act on its own* — detect a bad signal, page a human,
and recycle itself. It's the "auto-healing" the project is named for.

## The problem this solves

A dashboard only helps when someone is watching it. If matchmaking latency climbs,
5xx errors spike, a task wedges, or the service falls to zero tasks at 3am, nothing
happens until a person notices. This module closes that gap: CloudWatch alarms watch
the signals the app and platform already emit, an SNS topic notifies on every one of
them, and two of them additionally drive an automatic remediation — no human in the
loop for the recover-by-recycling case.

## Services & why

- **CloudWatch alarms** — five, on metrics already proven to resolve on the
  dashboard: app error-rate %, matchmaking p99 latency, ECS CPU, unhealthy hosts,
  and running-task-count. Each publishes to SNS.
- **SNS topic (+ optional email subscription)** — the notification fan-out. Email is
  the starter subscription; Discord/AWS Chatbot can subscribe to the same topic later.
- **EventBridge rule** — matches the *heal-trigger* alarms transitioning to `ALARM`
  and invokes the Lambda. Fires on the state transition, so a stuck alarm heals once.
- **Lambda (Python 3.12)** — calls `ecs update-service --force-new-deployment`,
  recycling the service's tasks through the existing blue/green process.

## Key decisions

- **Two heal triggers, not five.** Only *unhealthy hosts* and *no running tasks*
  force a redeploy — runtime-degradation signals a recycle can actually fix.
  Error-rate/latency/CPU are **notify-only**: error-rate especially stays out of the
  heal path so it can't race the compute deploy-rollback alarm on a bad build.
- **`treat_missing_data` is set per alarm, deliberately.** The default is wrong in
  opposite directions here — the error-rate ratio divides by zero at idle (so
  `notBreaching`, or an idle service self-heals in a loop), while Container Insights
  *stops publishing* `RunningTaskCount` at zero tasks (so `breaching`, or a fully-down
  service never fires).
- **The unhealthy-hosts alarm watches *both* target groups.** `UnHealthyHostCount`
  is published per (`LoadBalancer`, `TargetGroup`) pair and won't resolve without both
  dimensions — but ECS native blue/green moves production between the blue and green
  target groups on each deploy and leaves it there, so a single fixed `TargetGroup`
  goes blind after the first shift. The alarm is metric math on `MAX(blue, green)`
  (each group's absent datapoints filled to 0), so it follows production whichever
  color currently holds it.
- **The deploy-rollback alarm lives in `compute`, not here.** The ECS service must
  name it in its own `alarms{}` block; housing it here would create a
  compute→autoheal→compute module cycle. This module owns only the operational alarms.
- **Least-privilege heal.** The Lambda gets `ecs:UpdateService` + `ecs:DescribeServices`
  scoped to the one service ARN, plus its own logs. `force-new-deployment` re-registers
  nothing, so no `iam:PassRole`.
- **Cooldown guard against flapping.** EventBridge fires on every OK→ALARM edge, so a
  flapping alarm would otherwise force a redeploy each time and never let the service
  settle. Before healing, the Lambda reads the service's own deployment state (no
  external store) and skips if a deployment is already rolling out or the last one
  started within `heal_cooldown_seconds` (default 300s, ≥ the bake time). This is why
  the Lambda now needs `ecs:DescribeServices`. (Reserved concurrency of 1 would also
  serialize simultaneous alarms, but this account's Lambda concurrency limit is 10 and
  AWS forbids reserving below the unreserved floor of 10 — so the cooldown guard alone
  carries it; worst case is one redundant redeploy from two alarms firing at once.)

## How to deploy

Wired into `environments/dev` only today (staging/prod don't yet instantiate compute).
Created by the normal environment apply — no separate step. Set `notification_email`
in `terraform.tfvars` to get the email subscription (then confirm the SNS link AWS
emails you); leave it empty for the topic with no subscription.

Prove the loop without real load by forcing an alarm state:

```bash
aws cloudwatch set-alarm-state --alarm-name dev-skybound-no-running-tasks \
  --state-value ALARM --state-reason "manual heal-loop test"
# then watch: the remediate Lambda's logs, a new ECS deployment, and the SNS email.
```
