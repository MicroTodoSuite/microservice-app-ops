# Remote state in the fprd Azure state account (the state root's tfstate
# container) under fprd/registry/terraform.tfstate, locked by blob leases.
# Values come from registry.azurerm.tfbackend, copied from the committed example.
terraform {
  backend "azurerm" {}
}
