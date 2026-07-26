# (c) 2026 JFrog Ltd.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    platform = {
      source  = "jfrog/platform"
      version = ">= 2.2.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# Configure the JFrog Platform Provider
# Only used when assign_jfrog_iam_role is true (see platform_aws_iam_role in secret.tf)
provider "platform" {
  url          = "https://${var.jfrog_host}"
  access_token = var.jfrog_admin_token
}

check "jfrog_credentials_when_assigning" {
  assert {
    condition     = !var.assign_jfrog_iam_role || (length(var.jfrog_admin_username) > 0 && length(var.jfrog_admin_token) > 0)
    error_message = "jfrog_admin_username and jfrog_admin_token are required when assign_jfrog_iam_role is true."
  }
}

