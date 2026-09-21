# Remote state in the fprd Azure state account (the state root's tfstate
# container) under fprd/security/terraform.tfstate, locked by blob leases.
# Values come from security.azurerm.tfbackend, copied from the committed example.
terraform {
  backend "azurerm" {}
}
