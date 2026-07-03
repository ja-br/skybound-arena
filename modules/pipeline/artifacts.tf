# S3 artifact bucket — CodePipeline passes artifacts between stages here (the
# source checkout into the build, the image reference into the deploy). Same
# hardening as the state bucket: versioned, encrypted, no public access.
data "aws_caller_identity" "current" {}

locals {
  name          = "${var.env}-skybound-pipeline"
  artifact_name = "${var.env}-skybound-artifacts-${data.aws_caller_identity.current.account_id}"
  state_bucket  = "skybound-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifact_name

  # Dev-only convenience: let `terraform destroy` clean up a non-empty bucket.
  # Drop this in prod so artifacts can't be wiped by an accidental destroy.
  force_destroy = true

  tags = { Name = local.artifact_name }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
