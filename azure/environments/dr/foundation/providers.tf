# The principal provider, bound to the approved subscription. It authenticates
# through OIDC in CI or the operator's Azure CLI session, never a client secret
# (MTS-IAC-104). The storage account refuses shared keys, so storage calls use
# Entra ID.
provider "azurerm" {
  alias               = "principal"
  subscription_id     = var.subscription_id
  use_oidc            = true
  storage_use_azuread = true

  features {}
}
