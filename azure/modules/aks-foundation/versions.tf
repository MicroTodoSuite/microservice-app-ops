# Terraform and provider requirements of the aks-foundation module. The module
# declares a provider floor (PC-IAC-006) and receives its provider from the root
# through the azurerm.project alias (MTS-IAC-104).
terraform {
  required_version = ">= 1.15.8"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 5.0.1"
      configuration_aliases = [azurerm.project]
    }
  }
}
