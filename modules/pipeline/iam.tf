# All pipeline auth is IAM service roles — no static access keys anywhere. Two
# roles: one CodePipeline assumes to orchestrate stages, one CodeBuild assumes to
# do the actual Terraform work.

# --- CodePipeline service role -----------------------------------------------
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${local.name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  # Pass artifacts through the bucket.
  statement {
    sid     = "Artifacts"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  # Drive the build/deploy projects that belong to this pipeline set.
  statement {
    sid       = "RunBuilds"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = ["arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/${local.name}-*"]
  }

  # Pull the repo through the CodeConnections GitHub connection.
  statement {
    sid       = "UseConnection"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "${local.name}-codepipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

# --- CodeBuild service role (infra / Terraform) ------------------------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild_infra" {
  name               = "${local.name}-codebuild-infra"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild_infra" {
  # Build logs.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.name}-*"]
  }

  # Read the source artifact, write the plan artifact.
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  # Terraform remote state + native S3 locking (use_lockfile).
  statement {
    sid       = "State"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}", "arn:aws:s3:::${local.state_bucket}/*"]
  }

  # Terraform plan/apply of the full landing zone needs broad create/read/delete
  # across the stack's services. Scoped to those service namespaces (not *:*) and
  # to this account; tighten per-resource if you harden this for prod.
  statement {
    sid = "TerraformStack"
    actions = [
      "ec2:*", "ecs:*", "elasticloadbalancing:*", "dynamodb:*", "ecr:*",
      "logs:*", "iam:*", "s3:*", "cloudwatch:*", "application-autoscaling:*",
      "sns:*", "codebuild:*", "codepipeline:*", "codestar-connections:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild_infra" {
  name   = "${local.name}-codebuild-infra"
  role   = aws_iam_role.codebuild_infra.id
  policy = data.aws_iam_policy_document.codebuild_infra.json
}
