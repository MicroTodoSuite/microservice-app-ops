# The authenticated client, bound to the approved subscription: this root
# creates no resource group, so it carries the subscription guard itself.
data "azurerm_client_config" "current" {
  provider = azurerm.principal

  lifecycle {
    postcondition {
      condition     = self.subscription_id == var.subscription_id
      error_message = "The authenticated Azure client is not in the approved subscription; nothing is planned against another subscription."
    }
  }
}

# Resources of the workload and security roots, looked up by standard name
# (PC-IAC-017).
data "azurerm_kubernetes_cluster" "dr" {
  provider = azurerm.principal

  name                = "${local.governance_prefix}-aks-dr"
  resource_group_name = "${local.governance_prefix}-rg-workload"
}

data "azurerm_key_vault" "dr" {
  provider = azurerm.principal

  name                = "${local.governance_prefix}-kv-dr"
  resource_group_name = "${local.governance_prefix}-rg-security"
}
