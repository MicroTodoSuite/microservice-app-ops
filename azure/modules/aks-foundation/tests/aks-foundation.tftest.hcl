# Contract for the Azure disaster-recovery AKS foundation module
# (gitops specs/009-full-platform-rollout T118; implemented by T125).
#
# Every run plans offline against a mock AzureRM provider: no credentials, no
# subscription, and no Azure API call. The override_resource blocks below give
# the compared resources known identifiers at plan time, so identity, scope,
# and issuer wiring can be compared exactly.
#
# The module declares the `azurerm.project` configuration alias (MTS-IAC-104),
# so every run passes that provider explicitly.

mock_provider "azurerm" {
  alias           = "project"
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      client_id       = "11111111-1111-1111-1111-111111111111"
      object_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }

}

# Mock computed values are unknown at plan unless an override supplies them.
# Each override gives one resource distinct, well-formed identifiers so scope
# and identity wiring can be compared exactly. Overrides replace computed
# values only; an argument the configuration sets is never masked.

override_resource {
  target          = azurerm_resource_group.main
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr"
  }
}

override_resource {
  target          = azurerm_resource_group.ingress
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-ingress"
  }
}

override_resource {
  target          = azurerm_subnet.nodes
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.cluster
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-aks"
    principal_id = "aaaaaaaa-0000-0000-0000-00000000000a"
    client_id    = "aaaaaaaa-1111-1111-1111-11111111111a"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.kubelet
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
    principal_id = "bbbbbbbb-0000-0000-0000-00000000000b"
    client_id    = "bbbbbbbb-1111-1111-1111-11111111111b"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.key_vault_reader
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kvreader"
    principal_id = "cccccccc-0000-0000-0000-00000000000c"
    client_id    = "cccccccc-1111-1111-1111-11111111111c"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.github_seed
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-drseed"
    principal_id = "dddddddd-0000-0000-0000-00000000000d"
    client_id    = "dddddddd-1111-1111-1111-11111111111d"
  }
}

override_resource {
  target          = azurerm_kubernetes_cluster.this
  override_during = plan
  values = {
    id                  = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ContainerService/managedClusters/lex-mts-fprd-aks-dr"
    oidc_issuer_url     = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
    node_resource_group = "MC_lex-mts-fprd-rg-dr_lex-mts-fprd-aks-dr_eastus2"
  }
}

override_resource {
  target          = azurerm_key_vault.main
  override_during = plan
  values = {
    id            = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
    vault_uri     = "https://lex-mts-fprd-kv-dr.vault.azure.net/"
    access_policy = []
  }
}

override_resource {
  target          = azurerm_container_registry.main
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ContainerRegistry/registries/lexmtsfprdacrdr"
    login_server = "lexmtsfprdacrdr.azurecr.io"
  }
}

override_resource {
  target          = azurerm_role_definition.github_seed
  override_during = plan
  values = {
    role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/providers/Microsoft.Authorization/roleDefinitions/eeeeeeee-0000-0000-0000-00000000000e"
  }
}

override_resource {
  target          = azurerm_public_ip.ingress
  override_during = plan
  values = {
    ip_address = "203.0.113.10"
    fqdn       = "lex-mts-fprd-dr.abcdefgh.eastus2.cloudapp.azure.com"
  }
}

variables {
  client      = "lex"
  project     = "mts"
  environment = "fprd"

  subscription_id = "00000000-0000-0000-0000-00000000d0d0"
  location        = "eastus2"

  names = {
    resource_group            = "lex-mts-fprd-rg-dr"
    ingress_resource_group    = "lex-mts-fprd-rg-ingress"
    virtual_network           = "lex-mts-fprd-vnet-dr"
    node_subnet               = "lex-mts-fprd-snet-nodes"
    cluster                   = "lex-mts-fprd-aks-dr"
    cluster_identity          = "lex-mts-fprd-id-aks"
    kubelet_identity          = "lex-mts-fprd-id-kubelet"
    key_vault                 = "lex-mts-fprd-kv-dr"
    key_vault_reader_identity = "lex-mts-fprd-id-kvreader"
    github_seed_identity      = "lex-mts-fprd-id-drseed"
    github_seed_role          = "lex-mts-fprd-role-drseed"
    container_registry        = "lexmtsfprdacrdr"
    storage_account           = "lexmtsfprdstbackup"
    ingress_public_ip         = "lex-mts-fprd-pip-ingress"
  }

  kubernetes_version = "1.35"

  # Bounded cluster autoscaler within the subscription's regional vCPU quota
  # (MTS-IAC-104 records six vCPUs per region).
  system_node_pool = {
    vm_size   = "Standard_D2s_v5"
    vcpus     = 2
    min_count = 1
    max_count = 3
  }
  regional_vcpu_quota = 6

  cluster_admin_principal_ids = ["66666666-6666-6666-6666-666666666666"]

  # Placeholder ranges for the offline contract only. T124 selects the real
  # ranges from live Azure evidence; none of these is a selection.
  vnet_cidr        = "10.60.0.0/16"
  node_subnet_cidr = "10.60.0.0/22"
  pod_cidr         = "192.168.0.0/16"
  service_cidr     = "172.16.0.0/16"
  dns_service_ip   = "172.16.0.10"

  # Every AWS VPC in the rebuilt estate (eco, fstg, fprd, fdev, shd). The Azure
  # ranges must overlap none of them (spec 009 FR-008).
  reserved_cidrs = [
    "10.10.0.0/16",
    "10.20.0.0/16",
    "10.30.0.0/16",
    "10.40.0.0/16",
    "10.50.0.0/16",
  ]

  api_server_authorized_ip_ranges = [
    "181.50.102.191/32",
    "186.112.71.16/32",
    "190.108.77.190/32",
    "200.3.193.225/32",
  ]

  key_vault_reader_service_accounts = {
    prod = {
      namespace = "prod"
      name      = "external-secrets-jwt"
    }
    security = {
      namespace = "security"
      name      = "security-external-secrets-jwt"
    }
    observability = {
      namespace = "observability"
      name      = "observability-external-secrets-jwt"
    }
  }

  github_seed_subjects = ["repo:MicroTodoSuite/.github:environment:azure-dr"]

  key_vault_allowed_cidrs = [
    "181.50.102.191/32",
    "186.112.71.16/32",
    "190.108.77.190/32",
    "200.3.193.225/32",
  ]

  ingress_dns_label = "lex-mts-fprd-dr"

  common_tags = {
    Client      = "lex"
    Project     = "mts"
    Environment = "fprd"
    Owner       = "infrastructure"
    CostCenter  = "mts-full"
    ManagedBy   = "terraform"
    Repository  = "microservice-app-ops"
  }

  additional_tags = {
    Role = "disaster-recovery"
  }
}

run "network_cluster_and_identity_contract" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  # Subscription and location.

  assert {
    condition     = azurerm_resource_group.main.location == var.location && azurerm_resource_group.ingress.location == var.location
    error_message = "Both resource groups must be created in the approved location."
  }

  assert {
    condition = alltrue([
      for located in [
        azurerm_virtual_network.main,
        azurerm_kubernetes_cluster.this,
        azurerm_user_assigned_identity.cluster,
        azurerm_user_assigned_identity.kubelet,
        azurerm_user_assigned_identity.key_vault_reader,
        azurerm_user_assigned_identity.github_seed,
        azurerm_key_vault.main,
        azurerm_container_registry.main,
        azurerm_storage_account.backup,
        azurerm_public_ip.ingress,
      ] : located.location == var.location
    ])
    error_message = "Every located resource must be created in the approved location; nothing may drift to another region."
  }

  # Network ranges and private node subnet.

  assert {
    condition     = toset(azurerm_virtual_network.main.address_space) == toset([var.vnet_cidr])
    error_message = "The VNet must use exactly the verified VNet range."
  }

  assert {
    condition     = tolist(azurerm_subnet.nodes.address_prefixes) == tolist([var.node_subnet_cidr])
    error_message = "The node subnet must use exactly the verified node range."
  }

  assert {
    condition     = azurerm_subnet.nodes.virtual_network_name == azurerm_virtual_network.main.name && azurerm_subnet.nodes.resource_group_name == azurerm_resource_group.main.name
    error_message = "The node subnet must belong to the module's own VNet."
  }

  assert {
    condition     = azurerm_subnet.nodes.default_outbound_access_enabled == false
    error_message = "The node subnet must be private: default outbound access disabled, egress only through the cluster's explicit outbound path."
  }

  assert {
    condition     = toset([for endpoint in azurerm_subnet.nodes.service_endpoint : endpoint.service]) == toset(["Microsoft.KeyVault", "Microsoft.Storage"])
    error_message = "The node subnet must reach Key Vault and Storage through service endpoints, so both can deny public access by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].vnet_subnet_id == azurerm_subnet.nodes.id
    error_message = "The system node pool must run in the private node subnet."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled != true
    error_message = "Nodes must never receive a public IP address."
  }

  # AKS 1.35, Azure CNI Overlay, Cilium data plane and policy.

  assert {
    condition     = azurerm_kubernetes_cluster.this.kubernetes_version == "1.35"
    error_message = "AKS must run Kubernetes 1.35 (spec 009 research decision 9)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure" && azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay"
    error_message = "AKS must use Azure CNI in overlay mode."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium" && azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium"
    error_message = "AKS must use the Cilium data plane and enforce network policy with Cilium."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].pod_cidr == var.pod_cidr && azurerm_kubernetes_cluster.this.network_profile[0].service_cidr == var.service_cidr && azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip == var.dns_service_ip
    error_message = "AKS must use exactly the verified pod, service, and DNS ranges."
  }

  # Workload identity and OIDC issuer.

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == true && azurerm_kubernetes_cluster.this.workload_identity_enabled == true
    error_message = "AKS must enable the OIDC issuer and Microsoft Entra Workload ID."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "UserAssigned" && toset(azurerm_kubernetes_cluster.this.identity[0].identity_ids) == toset([azurerm_user_assigned_identity.cluster.id])
    error_message = "The cluster must run as exactly the module's user-assigned cluster identity, never a service principal."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.kubelet_identity[0].user_assigned_identity_id == azurerm_user_assigned_identity.kubelet.id && azurerm_kubernetes_cluster.this.kubelet_identity[0].client_id == azurerm_user_assigned_identity.kubelet.client_id && azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id == azurerm_user_assigned_identity.kubelet.principal_id
    error_message = "Nodes must pull images as the module's own pre-created kubelet identity, so its registry access is declared here rather than inherited from an AKS-created identity."
  }

  assert {
    condition     = azurerm_role_assignment.cluster_kubelet_identity_operator.scope == azurerm_user_assigned_identity.kubelet.id && azurerm_role_assignment.cluster_kubelet_identity_operator.role_definition_name == "Managed Identity Operator" && azurerm_role_assignment.cluster_kubelet_identity_operator.principal_id == azurerm_user_assigned_identity.cluster.principal_id
    error_message = "The cluster identity may operate the kubelet identity only, as AKS requires for a pre-created kubelet identity."
  }

  # API server allowlist.

  assert {
    condition     = toset(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges) == toset(var.api_server_authorized_ip_ranges)
    error_message = "The API server allowlist must equal the approved operator CIDRs exactly."
  }

  assert {
    condition     = !contains(tolist(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges), "0.0.0.0/0")
    error_message = "The API server allowlist must never contain 0.0.0.0/0."
  }

  # Kubernetes RBAC through Microsoft Entra ID, no local accounts.

  assert {
    condition     = azurerm_kubernetes_cluster.this.role_based_access_control_enabled == true && azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "AKS must enforce Kubernetes RBAC and disable local accounts, so every API call carries an Entra identity."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true && azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].tenant_id == data.azurerm_client_config.current.tenant_id
    error_message = "AKS must authorize Kubernetes access with Azure RBAC in the authenticated tenant."
  }

  assert {
    condition = length(azurerm_role_assignment.cluster_admin) == length(var.cluster_admin_principal_ids) && alltrue([
      for principal in var.cluster_admin_principal_ids :
      azurerm_role_assignment.cluster_admin[principal].scope == azurerm_kubernetes_cluster.this.id &&
      azurerm_role_assignment.cluster_admin[principal].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin" &&
      azurerm_role_assignment.cluster_admin[principal].principal_id == principal
    ])
    error_message = "Exactly the named operators, and no one else, must hold cluster administration, scoped to this cluster only."
  }

  # Bounded cluster autoscaler, no node auto-provisioning.

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_provisioning_profile[0].mode == "Manual"
    error_message = "Node auto-provisioning must stay off; capacity is the bounded cluster autoscaler only."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled == true && azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == var.system_node_pool.min_count && azurerm_kubernetes_cluster.this.default_node_pool[0].max_count == var.system_node_pool.max_count && azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size == var.system_node_pool.vm_size
    error_message = "The system node pool must autoscale between the reviewed bounds on the reviewed size."
  }

  # Dedicated ingress resource group and narrowly scoped cluster identity.

  assert {
    condition     = azurerm_resource_group.ingress.name == var.names.ingress_resource_group && azurerm_resource_group.ingress.name != azurerm_resource_group.main.name
    error_message = "The ingress public IP must live in its own dedicated resource group."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_resource_group != azurerm_resource_group.ingress.name
    error_message = "The AKS-managed node resource group must not be the ingress resource group; AKS must not own the address."
  }

  assert {
    condition     = azurerm_role_assignment.cluster_ingress_network.scope == azurerm_resource_group.ingress.id && azurerm_role_assignment.cluster_ingress_network.role_definition_name == "Network Contributor" && azurerm_role_assignment.cluster_ingress_network.principal_id == azurerm_user_assigned_identity.cluster.principal_id
    error_message = "The cluster identity must hold Network Contributor on the ingress resource group only."
  }

  assert {
    condition     = azurerm_role_assignment.cluster_subnet_network.scope == azurerm_subnet.nodes.id && azurerm_role_assignment.cluster_subnet_network.role_definition_name == "Network Contributor" && azurerm_role_assignment.cluster_subnet_network.principal_id == azurerm_user_assigned_identity.cluster.principal_id
    error_message = "The cluster identity's network access to its own VNet must be scoped to the node subnet, never the resource group or subscription."
  }

  # Standard static ingress public IP with a unique DNS label.

  assert {
    condition     = azurerm_public_ip.ingress.name == var.names.ingress_public_ip && azurerm_public_ip.ingress.resource_group_name == azurerm_resource_group.ingress.name
    error_message = "The ingress public IP must be the named address in the dedicated ingress resource group."
  }

  assert {
    condition     = azurerm_public_ip.ingress.sku == "Standard" && azurerm_public_ip.ingress.allocation_method == "Static"
    error_message = "The ingress public IP must be a Standard SKU static address."
  }

  assert {
    condition     = azurerm_public_ip.ingress.domain_name_label == var.ingress_dns_label && azurerm_public_ip.ingress.domain_name_label_scope == "TenantReuse"
    error_message = "The ingress public IP must carry the approved DNS label, scoped to the tenant so another tenant can never claim the same FQDN."
  }

  # Container registry.

  assert {
    condition     = azurerm_container_registry.main.name == var.names.container_registry && azurerm_container_registry.main.resource_group_name == azurerm_resource_group.main.name
    error_message = "The registry must be the named ACR in the DR resource group."
  }

  assert {
    condition     = azurerm_container_registry.main.admin_enabled == false && azurerm_container_registry.main.anonymous_pull_enabled != true
    error_message = "The registry must allow neither the admin user nor anonymous pulls; access is by Entra identity only."
  }

  assert {
    condition     = azurerm_role_assignment.kubelet_acr_pull.scope == azurerm_container_registry.main.id && azurerm_role_assignment.kubelet_acr_pull.role_definition_name == "AcrPull" && azurerm_role_assignment.kubelet_acr_pull.principal_id == azurerm_user_assigned_identity.kubelet.principal_id
    error_message = "The kubelet identity must hold only AcrPull, scoped to this registry."
  }

  # Encrypted storage.

  assert {
    condition     = azurerm_storage_account.backup.name == var.names.storage_account && azurerm_storage_account.backup.account_kind == "StorageV2"
    error_message = "The recovery storage account must be the named StorageV2 account."
  }

  assert {
    condition     = azurerm_storage_account.backup.infrastructure_encryption_enabled == true && azurerm_storage_account.backup.https_traffic_only_enabled == true && azurerm_storage_account.backup.min_tls_version == "TLS1_2"
    error_message = "The recovery storage account must use infrastructure (double) encryption and accept only HTTPS with TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.backup.shared_access_key_enabled == false && azurerm_storage_account.backup.allow_nested_items_to_be_public == false
    error_message = "The recovery storage account must refuse shared-key authorization and public blobs; access is by Entra identity only."
  }

  assert {
    condition     = azurerm_storage_account.backup.network_rules[0].default_action == "Deny" && toset(azurerm_storage_account.backup.network_rules[0].virtual_network_subnet_ids) == toset([azurerm_subnet.nodes.id]) && length(coalesce(azurerm_storage_account.backup.network_rules[0].ip_rules, [])) == 0
    error_message = "The recovery storage account must deny network access by default and admit only the node subnet."
  }

  assert {
    condition     = azurerm_storage_account.backup.blob_properties[0].versioning_enabled == true && azurerm_storage_account.backup.blob_properties[0].delete_retention_policy[0].days >= 7
    error_message = "The recovery storage account must keep blob versions and soft-delete blobs for at least seven days."
  }

  # Tags (MTS-IAC-104: AzureRM has no default_tags, so every resource merges them).

  assert {
    condition = alltrue([
      for tagged in [
        azurerm_resource_group.main,
        azurerm_resource_group.ingress,
        azurerm_virtual_network.main,
        azurerm_kubernetes_cluster.this,
        azurerm_user_assigned_identity.cluster,
        azurerm_user_assigned_identity.kubelet,
        azurerm_user_assigned_identity.key_vault_reader,
        azurerm_user_assigned_identity.github_seed,
        azurerm_key_vault.main,
        azurerm_container_registry.main,
        azurerm_storage_account.backup,
        azurerm_public_ip.ingress,
      ] : alltrue([for key, value in merge(var.common_tags, var.additional_tags) : lookup(tagged.tags, key, null) == value])
    ])
    error_message = "Every taggable resource must carry every common tag and every additional tag."
  }

  assert {
    condition = alltrue([
      azurerm_resource_group.main.tags["Name"] == var.names.resource_group,
      azurerm_resource_group.ingress.tags["Name"] == var.names.ingress_resource_group,
      azurerm_virtual_network.main.tags["Name"] == var.names.virtual_network,
      azurerm_kubernetes_cluster.this.tags["Name"] == var.names.cluster,
      azurerm_user_assigned_identity.cluster.tags["Name"] == var.names.cluster_identity,
      azurerm_user_assigned_identity.kubelet.tags["Name"] == var.names.kubelet_identity,
      azurerm_user_assigned_identity.key_vault_reader.tags["Name"] == var.names.key_vault_reader_identity,
      azurerm_user_assigned_identity.github_seed.tags["Name"] == var.names.github_seed_identity,
      azurerm_key_vault.main.tags["Name"] == var.names.key_vault,
      azurerm_container_registry.main.tags["Name"] == var.names.container_registry,
      azurerm_storage_account.backup.tags["Name"] == var.names.storage_account,
      azurerm_public_ip.ingress.tags["Name"] == var.names.ingress_public_ip,
    ])
    error_message = "Every taggable resource must set its Name tag to its own standard name."
  }

  # Outputs consumed by the DR root, GitOps (T129), and DNS (T134).

  assert {
    condition     = output.ingress_public_ip_name == azurerm_public_ip.ingress.name && output.ingress_public_ip_resource_group_name == azurerm_resource_group.ingress.name
    error_message = "The module must output the ingress public IP's name and resource group for the Istio Service annotations."
  }

  assert {
    condition     = output.ingress_public_ip_endpoint == azurerm_public_ip.ingress.ip_address && output.ingress_public_ip_dns_name == azurerm_public_ip.ingress.fqdn
    error_message = "The module must output the ingress public IP's address and provider FQDN for DNS."
  }

  assert {
    condition     = output.cluster_name == azurerm_kubernetes_cluster.this.name && output.oidc_issuer_url == azurerm_kubernetes_cluster.this.oidc_issuer_url && output.kubernetes_version == azurerm_kubernetes_cluster.this.kubernetes_version
    error_message = "The module must output the cluster name, OIDC issuer URL, and Kubernetes version."
  }

  assert {
    condition     = toset(output.api_server_authorized_cidrs) == toset(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges)
    error_message = "The module must output the allowlist the cluster actually carries, not a copy of the input."
  }

  assert {
    condition     = output.resource_group_name == azurerm_resource_group.main.name && output.container_registry_name == azurerm_container_registry.main.name && output.container_registry_endpoint == azurerm_container_registry.main.login_server && output.storage_account_name == azurerm_storage_account.backup.name
    error_message = "The module must output the resource group, registry, and storage account identifiers."
  }
}

run "empty_key_vault_and_access_boundaries" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  assert {
    condition     = azurerm_key_vault.main.name == var.names.key_vault && azurerm_key_vault.main.resource_group_name == azurerm_resource_group.main.name
    error_message = "The Key Vault must be the named vault in the DR resource group."
  }

  assert {
    condition     = azurerm_key_vault.main.rbac_authorization_enabled == true && length(azurerm_key_vault.main.access_policy) == 0
    error_message = "The Key Vault must authorize with Azure RBAC only; no access policy may exist (MTS-IAC-104)."
  }

  assert {
    condition     = azurerm_key_vault.main.purge_protection_enabled == true && azurerm_key_vault.main.soft_delete_retention_days >= 7 && azurerm_key_vault.main.soft_delete_retention_days <= 90
    error_message = "The Key Vault must enable purge protection with an explicit soft-delete retention (MTS-IAC-104)."
  }

  assert {
    condition     = azurerm_key_vault.main.tenant_id == data.azurerm_client_config.current.tenant_id
    error_message = "The Key Vault must trust the authenticated tenant only."
  }

  assert {
    condition     = azurerm_key_vault.main.network_acls[0].default_action == "Deny" && azurerm_key_vault.main.network_acls[0].bypass == "AzureServices" && toset(azurerm_key_vault.main.network_acls[0].virtual_network_subnet_ids) == toset([azurerm_subnet.nodes.id]) && toset(azurerm_key_vault.main.network_acls[0].ip_rules) == toset(var.key_vault_allowed_cidrs)
    error_message = "The Key Vault must deny network access by default and admit only the node subnet and the reviewed operator addresses."
  }

  # AKS workload reader: read-only, one vault, exact service-account subjects.

  assert {
    condition     = azurerm_role_assignment.key_vault_reader.scope == azurerm_key_vault.main.id && azurerm_role_assignment.key_vault_reader.role_definition_name == "Key Vault Secrets User" && azurerm_role_assignment.key_vault_reader.principal_id == azurerm_user_assigned_identity.key_vault_reader.principal_id
    error_message = "The AKS reader identity must hold only Key Vault Secrets User, scoped to this vault."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.key_vault_reader) == length(var.key_vault_reader_service_accounts)
    error_message = "The reader identity must trust exactly one federated credential per approved service account, and no other."
  }

  assert {
    condition = alltrue([
      for key, account in var.key_vault_reader_service_accounts :
      azurerm_federated_identity_credential.key_vault_reader[key].issuer == azurerm_kubernetes_cluster.this.oidc_issuer_url &&
      azurerm_federated_identity_credential.key_vault_reader[key].subject == "system:serviceaccount:${account.namespace}:${account.name}" &&
      tolist(azurerm_federated_identity_credential.key_vault_reader[key].audience) == tolist(["api://AzureADTokenExchange"]) &&
      azurerm_federated_identity_credential.key_vault_reader[key].user_assigned_identity_id == azurerm_user_assigned_identity.key_vault_reader.id
    ])
    error_message = "Each reader credential must trust this cluster's OIDC issuer, one exact service-account subject, and only the Entra token-exchange audience."
  }

  # GitHub seed: get/set/read-metadata data actions on this vault only.

  assert {
    condition     = toset(azurerm_role_definition.github_seed.permissions[0].data_actions) == toset(["Microsoft.KeyVault/vaults/secrets/getSecret/action", "Microsoft.KeyVault/vaults/secrets/setSecret/action", "Microsoft.KeyVault/vaults/secrets/readMetadata/action"])
    error_message = "The seed role may only get, set, and read the metadata of secrets; it may never delete, purge, back up, or restore them."
  }

  assert {
    condition     = length(coalesce(azurerm_role_definition.github_seed.permissions[0].actions, [])) == 0
    error_message = "The seed role must carry no control-plane action."
  }

  assert {
    condition     = azurerm_role_definition.github_seed.name == var.names.github_seed_role && azurerm_role_definition.github_seed.scope == azurerm_resource_group.main.id && toset(azurerm_role_definition.github_seed.assignable_scopes) == toset([azurerm_resource_group.main.id])
    error_message = "The seed role must be defined on, and assignable within, the DR resource group only; a custom role cannot be defined on a single resource."
  }

  assert {
    condition     = azurerm_role_assignment.github_seed.scope == azurerm_key_vault.main.id && azurerm_role_assignment.github_seed.role_definition_id == azurerm_role_definition.github_seed.role_definition_resource_id && azurerm_role_assignment.github_seed.principal_id == azurerm_user_assigned_identity.github_seed.principal_id
    error_message = "The seed role must be assigned to the seed identity on this vault only."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.github_seed) == length(var.github_seed_subjects)
    error_message = "The seed identity must trust exactly one federated credential per approved GitHub subject."
  }

  assert {
    condition = alltrue([
      for subject in var.github_seed_subjects :
      azurerm_federated_identity_credential.github_seed[subject].issuer == "https://token.actions.githubusercontent.com" &&
      azurerm_federated_identity_credential.github_seed[subject].subject == subject &&
      tolist(azurerm_federated_identity_credential.github_seed[subject].audience) == tolist(["api://AzureADTokenExchange"]) &&
      azurerm_federated_identity_credential.github_seed[subject].user_assigned_identity_id == azurerm_user_assigned_identity.github_seed.id
    ])
    error_message = "Each seed credential must trust GitHub Actions for one exact repository-and-environment subject only."
  }

  # Non-secret identifiers only.

  assert {
    condition     = output.key_vault_name == azurerm_key_vault.main.name && output.key_vault_url == azurerm_key_vault.main.vault_uri
    error_message = "The module must output the vault's name and URI, both non-secret."
  }

  assert {
    condition     = output.key_vault_reader_client_id == azurerm_user_assigned_identity.key_vault_reader.client_id && output.github_seed_client_id == azurerm_user_assigned_identity.github_seed.client_id
    error_message = "The module must output the reader and seed client IDs, which the workload annotation and the seed workflow consume."
  }
}

# Guards. Each run supplies exactly one invalid input and expects the plan to
# stop on that input, never to continue with a weakened configuration.

run "rejects_a_different_subscription" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  override_data {
    target          = data.azurerm_client_config.current
    override_during = plan
    values = {
      subscription_id = "99999999-9999-9999-9999-999999999999"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }

  expect_failures = [azurerm_resource_group.main]
}

run "rejects_a_malformed_subscription_id" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    subscription_id = "not-a-subscription"
  }

  expect_failures = [var.subscription_id]
}

run "rejects_a_display_name_location" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    location = "East US 2"
  }

  expect_failures = [var.location]
}

run "rejects_another_kubernetes_minor" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    kubernetes_version = "1.34"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_a_vnet_overlapping_an_aws_vpc" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  # 10.50.0.0/16 was the planned Azure range (spec 009 research decision 8);
  # the rebuilt shd hub VPC now owns it.
  variables {
    vnet_cidr        = "10.50.0.0/16"
    node_subnet_cidr = "10.50.0.0/22"
  }

  expect_failures = [var.vnet_cidr]
}

run "rejects_a_node_subnet_outside_the_vnet" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    node_subnet_cidr = "10.61.0.0/22"
  }

  expect_failures = [var.node_subnet_cidr]
}

run "rejects_a_pod_range_overlapping_the_vnet" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    pod_cidr = "10.60.128.0/17"
  }

  expect_failures = [var.pod_cidr]
}

run "rejects_a_pod_range_overlapping_an_aws_vpc" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    pod_cidr = "10.0.0.0/8"
  }

  expect_failures = [var.pod_cidr]
}

run "rejects_a_service_range_overlapping_the_vnet" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    service_cidr   = "10.60.192.0/18"
    dns_service_ip = "10.60.192.10"
  }

  expect_failures = [var.service_cidr]
}

run "rejects_a_service_range_overlapping_the_pod_range" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    service_cidr   = "192.168.0.0/20"
    dns_service_ip = "192.168.0.10"
  }

  expect_failures = [var.service_cidr]
}

run "rejects_a_dns_service_ip_outside_the_service_range" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    dns_service_ip = "172.17.0.10"
  }

  expect_failures = [var.dns_service_ip]
}

run "rejects_an_open_api_allowlist" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_a_non_host_api_allowlist_entry" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    api_server_authorized_ip_ranges = [
      "181.50.102.0/24",
      "186.112.71.16/32",
      "190.108.77.190/32",
      "200.3.193.225/32",
    ]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_an_empty_api_allowlist" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    api_server_authorized_ip_ranges = []
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_a_wildcard_reader_service_account" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    key_vault_reader_service_accounts = {
      prod = {
        namespace = "prod"
        name      = "*"
      }
    }
  }

  expect_failures = [var.key_vault_reader_service_accounts]
}

run "rejects_a_seed_subject_without_an_environment" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    github_seed_subjects = ["repo:MicroTodoSuite/.github:ref:refs/heads/main"]
  }

  expect_failures = [var.github_seed_subjects]
}

run "rejects_an_empty_seed_trust" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    github_seed_subjects = []
  }

  expect_failures = [var.github_seed_subjects]
}

run "rejects_an_invalid_dns_label" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    ingress_dns_label = "Lex_MTS"
  }

  expect_failures = [var.ingress_dns_label]
}

run "rejects_common_tags_without_the_required_keys" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    common_tags = {
      Project = "mts"
    }
  }

  expect_failures = [var.common_tags]
}

run "rejects_an_unknown_environment" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    environment = "prod"
  }

  expect_failures = [var.environment]
}

run "rejects_a_name_outside_the_governance_prefix" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    names = {
      resource_group            = "lex-mts-fprd-rg-dr"
      ingress_resource_group    = "lex-mts-fprd-rg-ingress"
      virtual_network           = "lex-mts-fprd-vnet-dr"
      node_subnet               = "lex-mts-fprd-snet-nodes"
      cluster                   = "aks-dr"
      cluster_identity          = "lex-mts-fprd-id-aks"
      kubelet_identity          = "lex-mts-fprd-id-kubelet"
      key_vault                 = "lex-mts-fprd-kv-dr"
      key_vault_reader_identity = "lex-mts-fprd-id-kvreader"
      github_seed_identity      = "lex-mts-fprd-id-drseed"
      github_seed_role          = "lex-mts-fprd-role-drseed"
      container_registry        = "lexmtsfprdacrdr"
      storage_account           = "lexmtsfprdstbackup"
      ingress_public_ip         = "lex-mts-fprd-pip-ingress"
    }
  }

  expect_failures = [var.names]
}

run "rejects_an_autoscaler_beyond_the_vcpu_quota" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    system_node_pool = {
      vm_size   = "Standard_D2s_v5"
      vcpus     = 2
      min_count = 1
      max_count = 4
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_an_autoscaler_minimum_above_its_maximum" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    system_node_pool = {
      vm_size   = "Standard_D2s_v5"
      vcpus     = 2
      min_count = 3
      max_count = 2
    }
  }

  expect_failures = [var.system_node_pool]
}

run "rejects_an_empty_cluster_admin_set" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    cluster_admin_principal_ids = []
  }

  expect_failures = [var.cluster_admin_principal_ids]
}

run "rejects_an_open_key_vault_allowlist" {
  command = plan

  providers = {
    azurerm.project = azurerm.project
  }

  variables {
    key_vault_allowed_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.key_vault_allowed_cidrs]
}
