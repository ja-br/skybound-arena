# Remote state for the staging environment.

terraform {
  backend "s3" {
    # bucket is account-specific — passed at init:
    #   -backend-config="bucket=skybound-tfstate-<ACCOUNT_ID>"
    key          = "env/staging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
