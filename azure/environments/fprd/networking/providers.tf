# The principal provider, bound to the approved subscription. It authenticates
# through OIDC in CI or the operator's Azure CLI session, never a client secret
# (MTS-IAC-104). Storage calls use Entra ID, because the accounts refuse shared
# keys; azurerm 5.0 registers no resource provider unless asked.
provider "azurerm" {
  alias                           = "principal"
  subscription_id                 = var.subscription_id
  use_oidc                        = true
  storage_use_azuread             = true
  resource_provider_registrations = "none"

  features {}
}
