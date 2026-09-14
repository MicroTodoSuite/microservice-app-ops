# Terraform and provider requirements of the eco/security-irsa root. The root pins the
# provider exactly (PC-IAC-006); the Terraform version itself is .terraform-version.
terraform {
  required_version = ">= 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.64.0"
    }
  }
}
