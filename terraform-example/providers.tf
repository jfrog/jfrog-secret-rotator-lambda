# (c) 2025 JFrog Ltd.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

check "jfrog_credentials_when_assigning" {
  assert {
    condition     = !var.assign_jfrog_iam_role || (length(var.jfrog_admin_username) > 0 && length(var.jfrog_admin_token) > 0)
    error_message = "jfrog_admin_username and jfrog_admin_token are required when assign_jfrog_iam_role is true."
  }
}

