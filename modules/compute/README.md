# compute module

The runtime the app runs on and the target the CI/CD pipeline deploys into: an
ECR repo, an internet-facing ALB with two target groups (blue/green), a
CloudWatch log group, scoped task/execution IAM roles, and a Fargate ECS service
that performs **ECS-native blue/green deployments**.

## How deploys work

The ECS service uses the built-in blue/green strategy
(`deployment_configuration { strategy = "BLUE_GREEN" }`). A deployment is
triggered by updating the service's **task definition** (new image). ECS then:

1. Provisions the new version as a **green** task set alongside the live **blue**
   one and registers it with the green target group.
2. Optionally validates green against a **test listener rule** using lifecycle
   hooks — the shift can be blocked until validation passes.
3. Shifts production traffic by repointing the **production listener rule** from
   blue to green.
4. **Bakes** for `bake_time_in_minutes`, then drains and stops blue.
5. **Auto-rolls back** to blue — no downtime — if a CloudWatch
   `deployment_alarm` fires or the deployment circuit breaker trips.

Traffic shifting is wired through ALB **listener rules**, and an **ECS
infrastructure IAM role** (managed policy
`AmazonECSInfrastructureRolePolicyForLoadBalancers`) grants ECS permission to
modify the target groups and listener rules during a shift. Terraform owns the
task-def template and the bootstrap revision; the app pipeline owns the running
revision, so the service sets `ignore_changes = [task_definition]` to keep an
apply from reverting the pipeline's live deploy.

## Bootstrap sequence

The ECR repo is empty on first apply, so the service can't pull an image yet.
Bring it up in two steps from `environments/dev/`:

```bash
# 1. Create just the ECR repo.
terraform apply -target=module.compute.aws_ecr_repository.app

# 2. Build the app and push it as :bootstrap.
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "${REPO%/*}"
docker build --platform linux/amd64 -t "$REPO:bootstrap" ../../app
docker push "$REPO:bootstrap"

# 3. Apply the rest (cluster, ALB, service, roles).
terraform apply
```

Then `curl http://$(terraform output -raw alb_dns_name)/healthz` — once it's
`200`, the deploy target is live and the app pipeline has somewhere to ship to.
`/version` will read `bootstrap` until the first pipeline deploy stamps it with a
git SHA.

## Dev vs prod

- **Listener:** dev uses HTTP:80 (no ACM cert). Set `certificate_arn` in
  staging/prod to switch the production listener to HTTPS:443.
- **ECR:** one repo per environment (`<env>-skybound-arena`), consistent with the
  per-environment isolation used everywhere else in this project.
