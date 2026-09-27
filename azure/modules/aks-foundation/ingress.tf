# The Terraform-owned static ingress address in its dedicated resource group,
# and the cluster identity's Network Contributor on that group only, so the
# Istio Service can bind the address by name without AKS owning it.

# The ingress address lives apart from the AKS-managed node resource group, so
# neither AKS nor a Kubernetes Service can delete or replace it.
resource "azurerm_resource_group" "ingress" {
  provider = azurerm.project

  name     = var.names.ingress_resource_group
  location = var.location
  tags     = merge(local.tags, { Name = var.names.ingress_resource_group })
}

# Terraform owns the address; the Istio Service only selects it by name and
# resource group. TenantReuse hashes the FQDN so no other tenant can claim it.
resource "azurerm_public_ip" "ingress" {
  provider = azurerm.project

  name                    = var.names.ingress_public_ip
  location                = var.location
  resource_group_name     = azurerm_resource_group.ingress.name
  sku                     = "Standard"
  allocation_method       = "Static"
  domain_name_label       = var.ingress_dns_label
  domain_name_label_scope = "TenantReuse"
  tags                    = merge(local.tags, { Name = var.names.ingress_public_ip })
}

resource "azurerm_role_assignment" "cluster_ingress_network" {
  provider = azurerm.project

  scope                = azurerm_resource_group.ingress.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}
