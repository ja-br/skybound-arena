# Remote state for the dev environment.

terraform {
  backend "s3" {
    bucket       = "skybound-tfstate-680458886009"
    key          = "env/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}