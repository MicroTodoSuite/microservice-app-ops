# The DR container registry: no admin user, no anonymous pull; nodes pull as
# the kubelet identity with AcrPull on this registry only.

resource "azurerm_container_registry" "main" {
  provider = azurerm.project

  name                   = var.names.container_registry
  location               = var.location
  resource_group_name    = azurerm_resource_group.main.name
  sku                    = "Standard"
  admin_enabled          = false
  anonymous_pull_enabled = false
  tags                   = merge(local.tags, { Name = var.names.container_registry })
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  provider = azurerm.project

  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type       = "ServicePrincipal"
}
