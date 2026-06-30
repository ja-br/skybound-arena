# Remote state for the staging environment.

terraform {
  backend "s3" {
    bucket       = "skybound-tfstate-680458886009"
    key          = "env/staging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
