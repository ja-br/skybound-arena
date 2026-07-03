# Skybound Arena — Landing Zone

A reusable, multi-environment AWS landing zone in Terraform. One command stands
up `dev`, `staging`, or `prod` with identical, secure networking. The secure
baseline every other piece of the platform deploys into.


## The problem this solves

Clicking through the console for deploying environs is inconsistent, insecure, and
slow. Game backends need clean public/private separation, servers must reach the
internet for players, but the player database and matchmaking logic must stay
private. This turns a multi-day manual setup into a one-command, parameterized
module so launching the next title starts from a secure baseline.

## Architecture

```
                  Internet
                     │
              ┌──────▼──────┐   public subnets (2 AZs)
              │  ALB (443)  │   SG: 443 from 0.0.0.0/0
              └──────┬──────┘
                     │  app SG: ingress ONLY from ALB SG
       ┌─────────────▼─────────────┐  private subnets (2 AZs)
       │   ECS/Fargate app tasks   │  no public IPs, egress via NAT
       └─────────────┬─────────────┘
                     │
              ┌──────▼──────┐
              │  DynamoDB   │  Players (+ leaderboard GSI), Matches
              └─────────────┘
```

- **VPC** across 2 AZs with public + private subnets, IGW, and NAT.
- **Public/private tier separation** the ALB is the only internet-facing
  thing; app tasks accept traffic *only* from the ALB SG; the data tier is fully
  private. No SSH anywhere (access is via SSM Session Manager).
- **DynamoDB** tables provisioned in code (`Players` with a `leaderboard-index`
  GSI for top-N queries, and `Matches`) so the app never clicks them.

> A rendered, environment-accurate version of this diagram lives in [`docs/architecture.png`](docs/architecture.png).

## Layout

```
bootstrap/            One-time: S3 state bucket (native lockfile locking)
modules/
  network/            VPC, subnets, IGW, NAT, route tables
  security/           ALB SG + app SG (ALB-only ingress)
  data/               DynamoDB Players (+ GSI) and Matches tables
  compute/            ECR, ALB, ECS/Fargate service (native blue/green)
  pipeline/           CodePipeline + CodeBuild (buildspecs inline)
environments/
  dev/                Wires the modules with dev-sized values
  staging/  prod/     Same shape, different scale (proves repeatability)
app/                  FastAPI backend
```

## Key decisions

- **Per-environment directories, not Terraform workspaces.** Each env has its own
  state key and is applied independently, so `apply` can never hit prod when you
  meant dev. Workspaces would be lighter but trade away that explicit isolation
- **Remote state in S3 with native lockfile locking.** State lives in a
  versioned, encrypted S3 bucket; concurrent applies are serialized by Terraform's
  native S3 lockfile (`use_lockfile`), introduced in Terraform 1.10
- **`PAY_PER_REQUEST` DynamoDB.** Game traffic is spiky and unpredictable,
  on-demand billing absorbs a streamer spike without pre-provisioned capacity
- **Cost knobs per env.** `nat_gateway_count = 1` in dev (one NAT is cheaper),
  bump to one-per-AZ in prod for HA, PITR off in dev, on in prod

## Deploy

**Prerequisites:** Terraform >= 1.10, AWS credentials configured
(`aws configure` / SSO), permission to create VPC + DynamoDB + S3 resources

**1. Bootstrap the state backend (once per account):**

```bash
cd bootstrap
terraform init
terraform apply
terraform output            # note the state_bucket name
```

**2. Stand up dev.** The state bucket is account-specific, so it's passed at
`init` — nothing account-specific is committed to the repo:

```bash
cd environments/dev
terraform init -backend-config="bucket=skybound-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform plan
terraform apply
```

Standing up `staging` or `prod` is the same commands in their directory

## Considered change for production

- One NAT gateway per AZ (already a variable) so a single AZ failure can't sever
  egress for the whole environment
- VPC interface endpoints for DynamoDB / ECR / SSM to keep traffic off the NAT
  (cheaper and more private at scale)
- The constant-PK `leaderboard-index` GSI is a hot partition at high write
  volume; at 1M players I'd shard the partition key or move ranking to a cache
- Tighten the app-task egress (currently `0.0.0.0/0`) to just what DynamoDB /
  ECR / SSM need
```
