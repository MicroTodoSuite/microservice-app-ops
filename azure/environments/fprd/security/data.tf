# Resources of the networking and registry roots, looked up by standard name
# (PC-IAC-017).
data "azurerm_subnet" "nodes" {
  provider = azurerm.principal

  name                 = "${local.governance_prefix}-snet-nodes"
  virtual_network_name = "${local.governance_prefix}-vnet-dr"
  resource_group_name  = "${local.governance_prefix}-rg-network"
}

data "azurerm_resource_group" "ingress" {
  provider = azurerm.principal

  name = "${local.governance_prefix}-rg-ingress"
}

data "azurerm_container_registry" "dr" {
  provider = azurerm.principal

  name                = "${local.compact_prefix}acrdr"
  resource_group_name = "${local.governance_prefix}-rg-registry"
}
