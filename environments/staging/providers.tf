terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }

  required_version = ">= 1.5"

}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "skybound"
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}
