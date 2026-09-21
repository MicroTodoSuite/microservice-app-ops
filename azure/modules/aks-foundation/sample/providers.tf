# The principal provider of the sample. The sample uses local state and no
# backend (PC-IAC-026); authentication comes from the Azure CLI or OIDC.
provider "azurerm" {
  alias               = "principal"
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {}
}

terraform {
  required_version = ">= 1.15.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.0.1"
    }
  }
}
