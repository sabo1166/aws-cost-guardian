terraform {
  required_version = ">= 1.11.0"

  # Partial configuration: bucket, key and region are passed by the workflow
  # (terraform init -backend-config=...). Native S3 locking, no DynamoDB table.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "aws-cost-guardian"
      ManagedBy = "terraform"
      Owner     = "mohammed-gamal"
    }
  }
}
