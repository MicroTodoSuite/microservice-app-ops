# main.tf - Terraform Backend Setup
# Proveedor de Azure
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Recurso: Grupo de recursos
resource "azurerm_resource_group" "terraform_state" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    Purpose = "TerraformState"
  }
}

# Recurso: Cuenta de almacenamiento
resource "azurerm_storage_account" "terraform_state" {
  name                     = "tfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.terraform_state.name
  location                 = azurerm_resource_group.terraform_state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = {
    Purpose = "TerraformState"
  }
}

# Recurso: Contenedor de Blob Storage
resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.terraform_state.id
  container_access_type = "private"
}

# Generador de string aleatorio para el nombre de la cuenta de almacenamiento
resource "random_string" "suffix" {
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}
