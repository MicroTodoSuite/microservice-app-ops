# The Azure disaster-recovery foundation (gitops specs/009-full-platform-rollout
# T125): the DR resource group, the AKS 1.35 cluster on Azure CNI Overlay with
# Cilium, and the encrypted recovery storage. The network, identities,
# registry, empty Key Vault, and ingress address live in the files the task
# names. Terraform never holds a secret value.

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
