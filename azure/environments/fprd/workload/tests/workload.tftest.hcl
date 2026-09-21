# Contract of the fprd Azure workload root (gitops
# specs/009-full-platform-rollout US5): the AKS DR cluster, bound to the
# networking root's private subnet and the security root's identities, and the
# encrypted recovery storage for off-provider copies (constitution principle
# 12). Plans offline against a mock provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# Lookups of the networking and security roots' resources by standard name.
override_data {
  target = data.azurerm_virtual_network.dr
  values = {
    address_space = ["10.70.0.0/16"]
  }
}

override_data {
  target = data.azurerm_subnet.nodes
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
  }
}

override_data {
  target = data.azurerm_user_assigned_identity.cluster
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-aks"
    principal_id = "aaaaaaaa-0000-0000-0000-00000000000a"
    client_id    = "aaaaaaaa-1111-1111-1111-11111111111a"
  }
}

override_data {
  target = data.azurerm_user_assigned_identity.kubelet
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
    principal_id = "bbbbbbbb-0000-0000-0000-00000000000b"
    client_id    = "bbbbbbbb-1111-1111-1111-11111111111b"
  }
}

# Offline placeholders; T124 verifies the real values and the operator-owned
# fprd.tfvars carries them (PC-IAC-024).
variables {
  client          = "lex"
  project         = "mts"
  environment     = "fprd"
  subscription_id = "00000000-0000-0000-0000-00000000d0d0"
  location        = "eastus2"
  pod_cidr        = "192.168.0.0/16"
  service_cidr    = "172.16.0.0/16"
  dns_service_ip  = "172.16.0.10"
  reserved_cidrs  = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "10.40.0.0/16", "10.50.0.0/16"]
  operator_cidrs = [
    "181.50.102.191/32",
    "186.112.71.16/32",
    "190.108.77.190/32",
    "200.3.193.225/32",
  ]
  system_node_pool = {
    vm_size   = "Standard_D2s_v5"
    vcpus     = 2
    min_count = 1
    max_count = 3
  }
  regional_vcpu_quota            = 6
  cluster_admin_group_object_ids = ["66666666-6666-6666-6666-666666666666"]
}

run "cluster_contract" {
  command = plan

  assert {
    condition     = local.resource_group.name == "lex-mts-fprd-rg-workload" && local.cluster.name == "lex-mts-fprd-aks-dr" && local.cluster.resource_group_name == "lex-mts-fprd-rg-workload" && local.cluster.kubernetes_version == "1.35"
    error_message = "The cluster must carry its MTS-IAC-101 name in the workload resource group and run Kubernetes 1.35."
  }

  assert {
    condition = local.cluster_identities == {
      cluster_identity_id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-aks"
      kubelet = {
        id        = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
        client_id = "bbbbbbbb-1111-1111-1111-11111111111b"
        object_id = "bbbbbbbb-0000-0000-0000-00000000000b"
      }
    }
    error_message = "The cluster must run as the security root's cluster and kubelet identities, looked up by name."
  }

  assert {
    condition = local.cluster_network == {
      subnet_id      = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
      vnet_cidr      = "10.70.0.0/16"
      pod_cidr       = "192.168.0.0/16"
      service_cidr   = "172.16.0.0/16"
      dns_service_ip = "172.16.0.10"
      reserved_cidrs = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "10.40.0.0/16", "10.50.0.0/16"]
    }
    error_message = "The cluster must use the networking root's node subnet and VNet range, and ranges checked against every AWS VPC."
  }

  assert {
    condition     = toset(output.api_server_authorized_cidrs) == toset(var.operator_cidrs)
    error_message = "The API server must admit exactly the four approved operator addresses (spec 009 FR-016)."
  }

  assert {
    condition     = output.cluster_name == "lex-mts-fprd-aks-dr" && output.kubernetes_version == "1.35"
    error_message = "The root must output the cluster name and version."
  }
}

run "recovery_storage_contract" {
  command = plan

  assert {
    condition     = local.recovery_storage.name == "lexmtsfprdstbackup" && local.recovery_storage.resource_group_name == "lex-mts-fprd-rg-workload" && local.recovery_storage.retention_days >= 30
    error_message = "The recovery account must carry its MTS-IAC-101 name and keep deleted copies for at least 30 days."
  }

  assert {
    condition     = local.recovery_storage_network_access.allowed_subnet_ids == ["/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"] && toset(local.recovery_storage_network_access.allowed_ip_addresses) == toset(["181.50.102.191", "186.112.71.16", "190.108.77.190", "200.3.193.225"])
    error_message = "The recovery account firewall must admit only the node subnet and the four operator addresses."
  }

  assert {
    condition     = local.recovery_containers == { backups = { name = "backups" } }
    error_message = "The recovery account must hold exactly one private backups container."
  }
}

run "rejects_a_fifth_operator_address" {
  command = plan

  variables {
    operator_cidrs = [
      "181.50.102.191/32",
      "186.112.71.16/32",
      "190.108.77.190/32",
      "200.3.193.225/32",
      "198.51.100.7/32",
    ]
  }

  expect_failures = [var.operator_cidrs]
}

run "rejects_another_environment" {
  command = plan

  variables {
    environment = "fstg"
  }

  expect_failures = [var.environment]
}
