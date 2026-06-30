# Bootstrap: creates the remote-state backend 
#   cd bootstrap
#   terraform init
#   terraform apply
#   terraform output            
# copy bucket/table names into environments/*/backend.tf


data "aws_caller_identity" "current" {}

locals {
  bucket_name = "skybound-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # prevent_destroy guards the state bucket against `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = "skybound"
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

