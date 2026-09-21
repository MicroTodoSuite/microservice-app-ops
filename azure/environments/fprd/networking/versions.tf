# Terraform and provider requirements of the fprd/networking Azure root. A root
# pins the exact provider release (PC-IAC-006).
terraform {
  required_version = ">= 1.15.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.0.1"
    }
  }
}
