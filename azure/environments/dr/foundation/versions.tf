# Terraform and provider requirements of the Azure DR foundation root. The root
# pins the exact AzureRM release (PC-IAC-006; spec 009 research decision 9).
terraform {
  required_version = ">= 1.15.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.0.1"
    }
  }
}
