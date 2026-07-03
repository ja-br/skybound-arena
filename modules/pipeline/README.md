# Skybound Arena — Zero-Downtime Pipeline

Two CodePipeline pipelines that ship *Skybound Arena* with no dropped player
sessions: one applies infrastructure (Terraform), one builds and blue/green
deploys the backend. Every stage runs under a scoped IAM service role — no static
keys anywhere.

## The problem this solves

*Skybound Arena* is live and players are mid-match 24/7. Pixel Forge pushes
balance patches and backend fixes weekly, but deploying by hand drops active
sessions and tanks the store rating. They need to ship the player-profile /
matchmaking API with **zero downtime** and **instant automatic rollback** when a
patch misbehaves — and a human gate so nothing reaches the environment
unreviewed.

## Architecture

```
 Infra pipeline    Source ──► Plan ──► Manual approval ──► Apply
 (Terraform)       (GitHub)  (build)   (human gate)       (terraform apply tfplan)

 App pipeline      Source ──► Build ──► Manual approval ──► Deploy
 (backend)         (GitHub)  (test +    (human gate)       (register task-def +
                             docker →                       update-service →
                             ECR :sha)                      ECS blue/green shift)
```

- **Source** — CodeConnections (GitHub App) pulls the repo on push to `main`. No
  personal access token stored; the connection ARN is the only reference.
- **Plan / Apply** — CodeBuild runs `init` / `fmt -check` / `validate` /
  `plan -out=tfplan`, a human approves, then Apply runs the *saved* plan — you
  approve exactly what runs, not a re-plan that may have drifted.
- **Build** — CodeBuild runs `pytest`, builds the image tagged with the commit
  SHA, pushes to ECR, and hands the image reference to Deploy.
- **Deploy** — registers a new task-def revision (new image, `VERSION`=SHA) and
  `update-service`; **ECS runs the native blue/green shift**, not a rolling update.

## Services & why

- **CodePipeline (×2, V2)** — one pipeline per concern. Infra and app change on
  different cadences and blast radii; splitting them keeps a code patch from ever
  triggering a `terraform apply`.
- **CodeBuild** — runs every step (Terraform, tests, `docker build`/push, the ECS
  deploy). Buildspecs are **inline in Terraform**, not loose `buildspec-*.yml`
  files, so the build contract lives with the pipeline that runs it.
- **CodeConnections (GitHub)** — a one-time OAuth handshake instead of a stored
  token. The single biggest credibility signal: the pipeline's access is a scoped
  connection, nothing static.
- **ECS-native blue/green** — ECS itself stands up green, health-checks it, shifts
  the listener, bakes, and drains blue. Replaced CodeDeploy (see
  `docs/adr/adr-001.md`) — one fewer moving part, and the rollout logic lives in
  the service definition.
- **Scoped IAM service roles** — CodePipeline, the Terraform build, and the app
  build each assume their own least-privilege role. The app deploy role can push
  to *this* ECR repo and update *this* service, nothing more.

## Key decisions

- **Two pipelines, not one.** Infra and app deploy independently; neither can
  accidentally drive the other.
- **Manual approval before anything lands.** Both pipelines pause at a `Manual`
  approval action — the "a human approves before it touches the environment" gate.
- **Ownership split on the task definition.** Terraform owns the durable service,
  LB wiring, and the bootstrap task-def; the app pipeline owns image rollouts. The
  service keeps `ignore_changes = [task_definition]` so a later apply doesn't
  revert the pipeline's live revision.
- **`/version` = git SHA, end to end.** The build bakes the commit SHA in as
  `VERSION`; `/version` returns it. After a deploy you `curl /version` and *see*
  the new SHA — the proof traffic shifted (and that rollback reverted it).
- **Auto-rollback via the deployment circuit breaker.** A green task set that
  fails `/healthz` during the bake window trips the circuit breaker and ECS drops
  back to blue — players never hit the broken build.

## How to deploy

**Prerequisites:** the landing zone (`environments/dev`) and the compute module
are already applied — this pipeline module is wired in `environments/dev/main.tf`
and comes up with them.

**1. Activate the GitHub connection (once).** Terraform creates the connection in
`PENDING` state — it can't complete the OAuth handshake for you. In the console:

```
CodePipeline → Settings → Connections → dev-skybound-pipeline-github
  → Update pending connection → install/authorize the AWS Connector for GitHub
  → pick the ja-br/skybound-arena repo
```

The connection status flips to **Available**. Until it does, the Source stage
fails.

**2. Trigger a run.** Push to `main`:

```bash
git push origin main
```

Both pipelines start from the Source stage automatically.

**3. Approve at the gate.** Each pipeline stops at its **Approval** stage. In the
console, open the pipeline (**CodePipeline → Pipelines →** click the pipeline
name), find the Approval stage, click **Review → Approve**. Or from the CLI:

```bash
TOKEN=$(aws codepipeline get-pipeline-state --name dev-skybound-pipeline-app \
  --query "stageStates[?stageName=='Approval'].actionStates[0].latestExecution.token" \
  --output text)
aws codepipeline put-approval-result --pipeline-name dev-skybound-pipeline-app \
  --stage-name Approval --action-name ManualApproval \
  --token "$TOKEN" --result summary=ok,status=Approved
```

**4. Watch the blue/green shift.** After approval the Deploy stage registers the
new revision and `update-service`s it; ECS stands up green, health-checks
`/healthz`, shifts the listener, bakes, and drains blue.

**5. Confirm it shifted.**

```bash
curl http://<alb-dns>/version      # returns the new commit SHA, not "bootstrap"
```

## What I'd change for production

- **Wire a CloudWatch deployment alarm** (5xx rate / p99 latency) as an
  additional rollback trigger alongside the circuit breaker.
- **Branch protection on `main`** requiring a PR review before merge, so the human
  gate starts at code review, not just the deploy.
- **Per-environment approval routing** via SNS → the team channel, so approvers
  get a link instead of polling the console.
