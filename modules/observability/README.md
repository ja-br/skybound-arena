# Observability — live-ops dashboard

The single pane of glass for the game backend: matchmaking health, HTTP errors,
and capacity on one screen. This module is the first slice of Project 3; alarms,
auto-healing, autoscaling, and cost alerts build on the signals it surfaces.

## The problem this solves

The backend used to run silently — if matchmaking slowed down or errors climbed
during a streamer spike, you'd find out from players, not a graph. You can't
alarm, autoscale, or auto-heal on signals that don't exist. This module gives the
one thing everything downstream needs first: a place to *see* how the service is
doing, in real time, during the exact traffic surge the project is built around.

## Services & why

- **CloudWatch dashboard** — one dashboard, three rows:
  - **Game signals** (custom app metrics): matchmaking latency p99, queue depth,
    matches made, players created.
  - **HTTP / edge**: app error-rate %, ALB request count + target 5xx, ALB target
    response time p99.
  - **Capacity** (ECS): CPU/memory utilization and running task count.
- **CloudWatch Embedded Metric Format (EMF)** — the app prints metrics as JSON to
  stdout; the ECS `awslogs` driver already shipping its logs carries them, and
  CloudWatch Logs auto-extracts them into metrics. No agent, no per-request AWS
  call on the hot path. This is the AWS-native form of the "emit cheaply, ship
  out-of-band" pattern (the same idea as StatsD/Prometheus).

## Key decisions

- **Custom game metrics, not just CPU.** Matchmaking latency and queue depth are
  what actually degrade for players under load; CPU alone hides that.
- **No metric-dimension cardinality traps.** `RequestCount`/`HttpErrorCount`
  aggregate at `service`/`env`; the request `route` and `status_class` ride along
  as *log fields*, not dimensions — so the error-rate widget is a clean
  service-level rate and there's no per-path metric explosion. Per-route detail
  stays queryable in Logs Insights.
- **One source of truth for the namespace/dimensions.** The metric namespace and
  `service` value come from the compute module's outputs — the same values it
  injects into the container — so the dashboard's metric references can't drift
  from what the app emits.
- **Correct ECS namespaces.** CPU/memory % come from `AWS/ECS`; `RunningTaskCount`
  comes from `ECS/ContainerInsights` (they live in different namespaces). Mixing
  them under one namespace renders empty graphs.
- **ALB widgets use the `LoadBalancer` dimension**, which is stable across a
  blue/green traffic shift (a target-group dimension goes blank after the cutover).

## How to deploy

Wired into `environments/dev` only today (staging/prod don't yet instantiate the
compute tier). It's created by the normal environment apply — no separate step:

```bash
cd environments/dev
terraform init -backend-config="bucket=skybound-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform apply
terraform output dashboard_url    # open it
```

The widgets populate once the app is serving traffic and emitting EMF (send some
requests, or run the k6 spike test). That populated dashboard is the screenshot
for the project README.
