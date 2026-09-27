# The authenticated client: its subscription is compared with the approved one,
# and its tenant is the only tenant the Key Vault and AKS RBAC trust.
data "azurerm_client_config" "current" {
  provider = azurerm.project
}
