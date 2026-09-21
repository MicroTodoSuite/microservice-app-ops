# Resources of the networking and security roots, looked up by standard name
# (PC-IAC-017).
data "azurerm_virtual_network" "dr" {
  provider = azurerm.principal

  name                = "${local.governance_prefix}-vnet-dr"
  resource_group_name = "${local.governance_prefix}-rg-network"
}

data "azurerm_subnet" "nodes" {
  provider = azurerm.principal

  name                 = "${local.governance_prefix}-snet-nodes"
  virtual_network_name = "${local.governance_prefix}-vnet-dr"
  resource_group_name  = "${local.governance_prefix}-rg-network"
}

data "azurerm_user_assigned_identity" "cluster" {
  provider = azurerm.principal

  name                = "${local.governance_prefix}-id-aks"
  resource_group_name = "${local.governance_prefix}-rg-security"
}

data "azurerm_user_assigned_identity" "kubelet" {
  provider = azurerm.principal

  name                = "${local.governance_prefix}-id-kubelet"
  resource_group_name = "${local.governance_prefix}-rg-security"
}
