# App pipeline build + deploy.
#
# Build: pytest, docker build (VERSION = git SHA), push to ECR as :<sha>, and
# emit image.txt. Deploy: base a new task-def revision on the live one with the
# new image + VERSION, register it, and update-service — ECS runs the native
# blue/green. The circuit breaker on the service auto-rolls-back a bad build.

locals {
  registry = split("/", var.ecr_repository_url)[0]

  app_build_buildspec = <<-YAML
    version: 0.2
    phases:
      install:
        runtime-versions:
          python: 3.12
        commands:
          - pip install -r app/requirements.txt
      pre_build:
        commands:
          - pytest app/tests
          - aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.registry}
          - IMAGE_URI=${var.ecr_repository_url}:$CODEBUILD_RESOLVED_SOURCE_VERSION
      build:
        commands:
          - docker build --build-arg VERSION=$CODEBUILD_RESOLVED_SOURCE_VERSION -t $IMAGE_URI app/
          - docker push $IMAGE_URI
      post_build:
        commands:
          - printf '%s' "$IMAGE_URI" > image.txt
    artifacts:
      files:
        - image.txt
  YAML

  app_deploy_buildspec = <<-YAML
    version: 0.2
    phases:
      build:
        commands:
          - IMAGE_URI=$(cat image.txt)
          - SHA=$${IMAGE_URI##*:}
          - aws ecs describe-task-definition --task-definition ${var.task_family} --region ${var.region} --query taskDefinition > td.json
          - jq --arg IMG "$IMAGE_URI" --arg NAME "${var.container_name}" --arg SHA "$SHA" '(.containerDefinitions[] | select(.name==$NAME) | .image) = $IMG | (.containerDefinitions[] | select(.name==$NAME) | .environment) |= map(if .name=="VERSION" then .value=$SHA else . end) | del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)' td.json > new-td.json
          - NEW_ARN=$(aws ecs register-task-definition --cli-input-json file://new-td.json --region ${var.region} --query taskDefinition.taskDefinitionArn --output text)
          - aws ecs update-service --cluster ${var.ecs_cluster_name} --service ${var.ecs_service_name} --task-definition $NEW_ARN --region ${var.region}
  YAML
}

# --- CodeBuild service role (app build + deploy) ------------------------------
resource "aws_iam_role" "codebuild_app" {
  name               = "${local.name}-codebuild-app"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild_app" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.name}-*"]
  }

  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  # ECR login is account-wide; push/pull is scoped to this repo.
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
    ]
    resources = [var.ecr_repository_arn]
  }

  # Register a new revision and roll it out. Register/Describe have no
  # resource-level support; UpdateService/DescribeServices scope to the service.
  statement {
    sid       = "EcsRegister"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }
  statement {
    sid       = "EcsDeploy"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"]
  }

  # register-task-definition passes the task + execution roles.
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codebuild_app" {
  name   = "${local.name}-codebuild-app"
  role   = aws_iam_role.codebuild_app.id
  policy = data.aws_iam_policy_document.codebuild_app.json
}

# --- CodeBuild projects ------------------------------------------------------
resource "aws_codebuild_project" "app_build" {
  name         = "${local.name}-app-build"
  service_role = aws_iam_role.codebuild_app.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = true # docker build/push
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.app_build_buildspec
  }
}

resource "aws_codebuild_project" "app_deploy" {
  name         = "${local.name}-app-deploy"
  service_role = aws_iam_role.codebuild_app.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.app_deploy_buildspec
  }
}
