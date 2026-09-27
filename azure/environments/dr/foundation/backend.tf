# Remote state in the approved Azure Blob backend, locked by blob leases, under
# its own key (PC-IAC-008). Values come from foundation.azurerm.tfbackend,
# copied from the committed example and verified by the DR preflight.
terraform {
  backend "azurerm" {}
}
