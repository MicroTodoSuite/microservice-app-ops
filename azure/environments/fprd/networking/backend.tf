# Remote state in the fprd Azure state account (the state root's tfstate
# container) under fprd/networking/terraform.tfstate, locked by blob leases.
# Values come from networking.azurerm.tfbackend, copied from the committed example.
terraform {
  backend "azurerm" {}
}
