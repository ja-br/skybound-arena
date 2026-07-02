# compute module

The runtime the app runs on and the target the CI/CD pipeline
deploys into: an ECR repo, an internet-facing ALB with two target groups
(blue/green), a CloudWatch log group, scoped task/execution IAM roles, and a
Fargate ECS service using the **CodeDeploy deployment controller**.


Terraform stands the service up once with a *bootstrap* task revision pointed at
the **blue** target group. CodeDeploy owns every deploy after. it
registers new task revisions and shifts the ALB listener between blue and green.
So the service ignores drift on `task_definition`, `load_balancer`, and
`desired_count`, and the listener ignores `default_action`. 

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
`200`, the deploy target is live and app pipeline has somewhere to
ship to. `/version` will read `bootstrap` until the first pipeline deploy stamps
it with a git SHA.

## Dev vs prod

- **Listener:** dev uses HTTP:80 (no ACM cert). Set `certificate_arn` in
  staging/prod to switch the production listener to HTTPS:443.
- **ECR:** one repo per environment (`<env>-skybound-arena`), consistent with the
  per-environment isolation used everywhere else in this project.
