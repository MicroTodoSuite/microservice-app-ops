# The DR VNet and its one private node subnet, with the Key Vault and Storage
# service endpoints that let both deny public access by default.

resource "azurerm_virtual_network" "main" {
  provider = azurerm.project

  name                = var.names.virtual_network
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
  tags                = merge(local.tags, { Name = var.names.virtual_network })
}

# Private subnet: no default outbound access; nodes leave only through the
# cluster's Standard Load Balancer. Service endpoints let Key Vault and the
# recovery storage account deny public access by default.
resource "azurerm_subnet" "nodes" {
  provider = azurerm.project

  name                            = var.names.node_subnet
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [var.node_subnet_cidr]
  default_outbound_access_enabled = false

  service_endpoint {
    service = "Microsoft.KeyVault"
  }

  service_endpoint {
    service = "Microsoft.Storage"
  }
}
