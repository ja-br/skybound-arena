# CodeBuild projects for the infra pipeline. Both install a pinned Terraform and
# run against the repo checked out by the Source stage.
#
# The Plan project ships the *entire repo plus the saved tfplan* as its output
# artifact, so the Apply project applies exactly the plan a human approved — no
# re-plan that could have drifted between the gate and the apply.

locals {
  codebuild_image = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
  tf_url          = "https://releases.hashicorp.com/terraform/${var.tf_version}/terraform_${var.tf_version}_linux_amd64.zip"

  plan_buildspec = <<-YAML
    version: 0.2
    phases:
      install:
        commands:
          - curl -sLo /tmp/tf.zip ${local.tf_url}
          - unzip -o -d /usr/local/bin /tmp/tf.zip
      build:
        commands:
          - cd ${var.tf_working_dir}
          - terraform init
          - terraform fmt -check
          - terraform validate
          - terraform plan -out=tfplan
    artifacts:
      files:
        - '**/*'
  YAML

  apply_buildspec = <<-YAML
    version: 0.2
    phases:
      install:
        commands:
          - curl -sLo /tmp/tf.zip ${local.tf_url}
          - unzip -o -d /usr/local/bin /tmp/tf.zip
      build:
        commands:
          - cd ${var.tf_working_dir}
          - terraform init
          - terraform apply -auto-approve tfplan
  YAML
}

resource "aws_codebuild_project" "tf_plan" {
  name         = "${local.name}-tf-plan"
  service_role = aws_iam_role.codebuild_infra.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.plan_buildspec
  }
}

resource "aws_codebuild_project" "tf_apply" {
  name         = "${local.name}-tf-apply"
  service_role = aws_iam_role.codebuild_infra.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = local.apply_buildspec
  }
}
