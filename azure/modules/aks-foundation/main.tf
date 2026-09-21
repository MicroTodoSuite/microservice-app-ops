# The Azure disaster-recovery foundation (gitops specs/009-full-platform-rollout
# T125): one AKS 1.35 cluster on Azure CNI Overlay with Cilium in a private
# node subnet, its identities, an empty RBAC-only Key Vault with exact reader
# and seed boundaries, a registry, encrypted recovery storage, and the static
# ingress address the GitOps Istio Service binds to. Terraform never holds a
# secret value: the vault starts empty and only the seed workflow writes it.

# Resource groups ---------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  provider = azurerm.project

  name     = var.names.resource_group
  location = var.location
  tags     = merge(local.tags, { Name = var.names.resource_group })

  lifecycle {
    precondition {
      condition     = data.azurerm_client_config.current.subscription_id == var.subscription_id
      error_message = "The authenticated Azure client is not in the approved subscription; nothing is planned against another subscription."
    }
  }
}

# The ingress address lives apart from the AKS-managed node resource group, so
# neither AKS nor a Kubernetes Service can delete or replace it.
resource "azurerm_resource_group" "ingress" {
  provider = azurerm.project

  name     = var.names.ingress_resource_group
  location = var.location
  tags     = merge(local.tags, { Name = var.names.ingress_resource_group })
}

# Network ---------------------------------------------------------------------

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

# Identities --------------------------------------------------------------------

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

resource "azurerm_user_assigned_identity" "key_vault_reader" {
  provider = azurerm.project

  name                = var.names.key_vault_reader_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.key_vault_reader_identity })
}

resource "azurerm_user_assigned_identity" "github_seed" {
  provider = azurerm.project

  name                = var.names.github_seed_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.github_seed_identity })
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

resource "azurerm_role_assignment" "cluster_ingress_network" {
  provider = azurerm.project

  scope                = azurerm_resource_group.ingress.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

# Cluster ---------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  provider = azurerm.project

  name                = var.names.cluster
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.names.cluster
  kubernetes_version  = var.kubernetes_version

  # Patch upgrades stay inside the reviewed 1.35 minor.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  role_based_access_control_enabled = true
  local_account_disabled            = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  # Capacity is the bounded cluster autoscaler only; node auto-provisioning
  # would add nodes outside the reviewed quota.
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                        = "system"
    temporary_name_for_rotation = "systemtmp"
    vm_size                     = var.system_node_pool.vm_size
    vnet_subnet_id              = azurerm_subnet.nodes.id
    node_public_ip_enabled      = false
    auto_scaling_enabled        = true
    min_count                   = var.system_node_pool.min_count
    max_count                   = var.system_node_pool.max_count
    tags                        = merge(local.tags, { Name = var.names.cluster })
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = merge(local.tags, { Name = var.names.cluster })

  # AKS validates both permissions when it creates the cluster.
  depends_on = [
    azurerm_role_assignment.cluster_subnet_network,
    azurerm_role_assignment.cluster_kubelet_identity_operator,
  ]
}

resource "azurerm_role_assignment" "cluster_admin" {
  provider = azurerm.project
  for_each = var.cluster_admin_principal_ids

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# Registry ----------------------------------------------------------------------

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

# Key Vault: empty, RBAC only, closed by default --------------------------------

resource "azurerm_key_vault" "main" {
  provider = azurerm.project

  name                       = var.names.key_vault
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.key_vault_allowed_cidrs
    virtual_network_subnet_ids = [azurerm_subnet.nodes.id]
  }

  tags = merge(local.tags, { Name = var.names.key_vault })

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "key_vault_reader" {
  provider = azurerm.project

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.key_vault_reader.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_federated_identity_credential" "key_vault_reader" {
  provider = azurerm.project
  for_each = var.key_vault_reader_service_accounts

  name                      = "kvreader-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.key_vault_reader.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
}

# The seed may get, set, and read the metadata of secrets, never delete, purge,
# back up, or restore them. A custom role cannot be defined on one resource, so
# it is defined on the resource group and assigned on the vault alone.
resource "azurerm_role_definition" "github_seed" {
  provider = azurerm.project

  name        = var.names.github_seed_role
  scope       = azurerm_resource_group.main.id
  description = "Seed the disaster-recovery Key Vault with the approved secret values; no delete, purge, backup, or restore."

  permissions {
    actions = []
    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action",
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.main.id]
}

resource "azurerm_role_assignment" "github_seed" {
  provider = azurerm.project

  scope              = azurerm_key_vault.main.id
  role_definition_id = azurerm_role_definition.github_seed.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github_seed.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_federated_identity_credential" "github_seed" {
  provider = azurerm.project
  for_each = var.github_seed_subjects

  name                      = "drseed-${substr(sha256(each.value), 0, 16)}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_seed.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
}

# Recovery storage: double encryption, Entra-only, closed by default ------------

resource "azurerm_storage_account" "backup" {
  provider = azurerm.project

  name                              = var.names.storage_account
  location                          = var.location
  resource_group_name               = azurerm_resource_group.main.name
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = []
    virtual_network_subnet_ids = [azurerm_subnet.nodes.id]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = merge(local.tags, { Name = var.names.storage_account })

  # Recovery copies must outlive any teardown of the cluster.
  lifecycle {
    prevent_destroy = true
  }
}

# Static ingress address ----------------------------------------------------------

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
