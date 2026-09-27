# The cluster and kubelet identities and the cluster's permissions, each on the
# narrowest scope AKS needs, plus Kubernetes administration for the named
# operators only.

resource "azurerm_user_assigned_identity" "cluster" {
  provider = azurerm.project

  name                = var.names.cluster_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.cluster_identity })
}

resource "azurerm_user_assigned_identity" "kubelet" {
  provider = azurerm.project

  name                = var.names.kubelet_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.kubelet_identity })
}

# The cluster identity's permissions, each on the narrowest scope AKS needs: the
# node subnet it joins, the kubelet identity it assigns, and the ingress
# resource group whose address its load balancer uses.
resource "azurerm_role_assignment" "cluster_subnet_network" {
  provider = azurerm.project

  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cluster_kubelet_identity_operator" {
  provider = azurerm.project

  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cluster_admin" {
  provider = azurerm.project
  for_each = var.cluster_admin_principal_ids

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}
