# Pipeline 1 — Infrastructure (Terraform).
#
#   Source (GitHub) -> Plan (CodeBuild) -> Manual approval -> Apply (CodeBuild)
#
# On-brand recursion: this pipeline lives in the same state it deploys, so once
# it exists it manages itself. The Manual approval action is the "a human
# approves before anything touches the environment" gate.
resource "aws_codepipeline" "infra" {
  name          = "${local.name}-infra"
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["src"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repository
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["src"]
      output_artifacts = ["plan"]
      configuration    = { ProjectName = aws_codebuild_project.tf_plan.name }
    }
  }

  stage {
    name = "Approval"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan"]
      configuration   = { ProjectName = aws_codebuild_project.tf_apply.name }
    }
  }
}

# Pipeline 2 — App build + blue/green deploy.
#
#   Source (GitHub) -> Build+test (CodeBuild) -> Manual approval -> Deploy (CodeBuild)
#
# Deploy registers a new task-def revision and update-services it; ECS runs the
# native blue/green shift, with the service's circuit breaker as auto-rollback.
resource "aws_codepipeline" "app" {
  name          = "${local.name}-app"
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["app_src"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repository
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["app_src"]
      output_artifacts = ["app_image"]
      configuration    = { ProjectName = aws_codebuild_project.app_build.name }
    }
  }

  stage {
    name = "Approval"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["app_image"]
      configuration   = { ProjectName = aws_codebuild_project.app_deploy.name }
    }
  }
}
