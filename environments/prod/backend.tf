# Remote state for the prod environment.

terraform {
  backend "s3" {
    # bucket is account-specific — passed at init:
    #   -backend-config="bucket=skybound-tfstate-<ACCOUNT_ID>"
    key          = "env/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
