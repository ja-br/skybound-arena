# Skybound Arena — Backend API


A deployable, observable, rollback-able service to prove out a
real delivery platform, demo blue/green deploys, health checks,
and ELO leaderboards under a "streamer spike" load test.

## Endpoints (8)

| Method | Path | Purpose |
|---|---|---|
| GET  | `/healthz` | Liveness for the ALB target group; the blue/green shift gates on it. |
| GET  | `/version` | Echoes the build's git SHA (injected by the pipeline). The proof traffic shifted. |
| POST | `/players` | Create a player (`{"username": "..."}`). Starts at rating 1000. |
| GET  | `/players/{player_id}` | Fetch a profile. |
| POST | `/matchmaking/queue` | Join the in-memory queue; pairs two waiting players into a match. |
| GET  | `/matchmaking/tickets/{ticket_id}` | Poll ticket status (`QUEUED` / `MATCHED`). |
| POST | `/matches/{match_id}/result` | Report a winner; applies simple ELO and updates wins/losses. |
| GET  | `/leaderboard?limit=10` | Top-N by rating via the `leaderboard-index` GSI. |


## Services & why

- **FastAPI** — auto OpenAPI docs, container-friendly, minimal boilerplate.
- **DynamoDB** — serverless, no DB to run
  `modules/data` (`${env}-Players` with the `leaderboard-index` GSI, `${env}-Matches`).
- **ECS/Fargate behind an ALB** — where the image runs; the app SG accepts
  `8080` only from the ALB SG 

## Key decisions

- **Stateless container, in-memory matchmaking.** The queue lives in the
  process on purpose — it makes the case for a real queue (SQS/DynamoDB) when
  you scale past one task. Honest about the trade-off rather than hiding it.
- **Rating is the GSI sort key.** Top-N leaderboard is a single `Query`
  (constant `entity = "PLAYER"` PK, `rating` SK, descending) — no scans.
- **`VERSION` env var → `/version`.** The Dockerfile bakes in the git SHA at
  build time; `/version` returns it. This is the load-bearing chain that proves
  blue/green shifted traffic (and that rollback reverted it).
- **ELO rounded to int** so it slots into the DynamoDB Number attribute and the
  leaderboard ordering stays stable. The math is the one real unit test in CI.

## Run it locally (no AWS account)

```bash
cd app
docker compose up --build      # DynamoDB Local + table init + API on :8080
curl localhost:8080/healthz
curl -X POST localhost:8080/players -d '{"username":"nova"}' -H 'content-type: application/json'
curl localhost:8080/leaderboard
```

## Test

```bash
cd app
python -m pytest tests          # ELO math + /healthz + /version
```

The CI buildspec runs `pytest app/tests` before building the image.


The app owns its own deploy contract:

- **`Dockerfile`** — build context is `app/`; takes `--build-arg VERSION=<sha>`.
  Container name `skybound-api` and port `8080` must stay in lockstep with the
  compute module's task definition and the app SG. The pipeline's deploy stage
  rebuilds the task-def revision from the live one (`aws ecs
  describe-task-definition`), swapping the image and `VERSION` — there is no
  separate task-def file to keep in sync.

## What I'd change for production

- Replace in-memory matchmaking with SQS or a DynamoDB-backed queue so tasks are
  truly stateless and matches survive a redeploy.
- API-key auth on write endpoints.
- Idempotency keys on `/matches/*/result` to make result reporting safe to retry.
