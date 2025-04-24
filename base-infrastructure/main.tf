# Backend configuration
terraform {
  backend "azurerm" {
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Resource Group Module
module "resource_group" {
  source   = "./modules/resource_group"
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Container Registry Module
module "container_registry" {
  source              = "./modules/container_registry"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  acr_name            = var.acr_name
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled
  tags                = var.tags
  depends_on          = [module.resource_group]
}

# Container Apps Environment Module
module "container_apps_environment" {
  source              = "./modules/container_apps_environment"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = var.container_apps_environment_name
  tags                = var.tags
  depends_on          = [module.resource_group]
}

