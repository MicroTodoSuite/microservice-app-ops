# Contract for the Azure disaster-recovery foundation root
# (gitops specs/009-full-platform-rollout T119; implemented by T126).
#
# Every run plans offline against a mock AzureRM provider: no credentials, no
# subscription, no backend, and no Azure call. What terraform test cannot see
# (the backend block, the absence of secret resources, and static credentials
# in the source) is checked by tests/contract/azure-dr-foundation.sh.
#
# The root configures `provider "azurerm"` with `alias = "principal"`
# (MTS-IAC-104) and passes it to the module as `azurerm.project`.

mock_provider "azurerm" {
  alias           = "principal"
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
  target          = module.aks_foundation.azurerm_resource_group.main
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_resource_group.ingress
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-ingress"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_subnet.nodes
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_user_assigned_identity.cluster
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-aks"
    principal_id = "aaaaaaaa-0000-0000-0000-00000000000a"
    client_id    = "aaaaaaaa-1111-1111-1111-11111111111a"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_user_assigned_identity.kubelet
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
    principal_id = "bbbbbbbb-0000-0000-0000-00000000000b"
    client_id    = "bbbbbbbb-1111-1111-1111-11111111111b"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_user_assigned_identity.key_vault_reader
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kvreader"
    principal_id = "cccccccc-0000-0000-0000-00000000000c"
    client_id    = "cccccccc-1111-1111-1111-11111111111c"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_user_assigned_identity.github_seed
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-drseed"
    principal_id = "dddddddd-0000-0000-0000-00000000000d"
    client_id    = "dddddddd-1111-1111-1111-11111111111d"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_kubernetes_cluster.this
  override_during = plan
  values = {
    id                  = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ContainerService/managedClusters/lex-mts-fprd-aks-dr"
    oidc_issuer_url     = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
    node_resource_group = "MC_lex-mts-fprd-rg-dr_lex-mts-fprd-aks-dr_eastus2"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_key_vault.main
  override_during = plan
  values = {
    id            = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
    vault_uri     = "https://lex-mts-fprd-kv-dr.vault.azure.net/"
    access_policy = []
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_container_registry.main
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-dr/providers/Microsoft.ContainerRegistry/registries/lexmtsfprdacrdr"
    login_server = "lexmtsfprdacrdr.azurecr.io"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_role_definition.github_seed
  override_during = plan
  values = {
    role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/providers/Microsoft.Authorization/roleDefinitions/eeeeeeee-0000-0000-0000-00000000000e"
  }
}

override_resource {
  target          = module.aks_foundation.azurerm_public_ip.ingress
  override_during = plan
  values = {
    ip_address = "203.0.113.10"
    fqdn       = "lex-mts-fprd-dr.abcdefgh.eastus2.cloudapp.azure.com"
  }
}

# Environment configuration arrives from the operator-owned .tfvars
# (PC-IAC-024); these are offline placeholders. Subscription, location, and
# every network range are the values T124 verifies from the live account; none
# of these is a selection.
variables {
  client      = "lex"
  project     = "mts"
  environment = "fprd"

  subscription_id  = "00000000-0000-0000-0000-00000000d0d0"
  location         = "eastus2"
  vnet_cidr        = "10.60.0.0/16"
  node_subnet_cidr = "10.60.0.0/22"
  pod_cidr         = "192.168.0.0/16"
  service_cidr     = "172.16.0.0/16"
  dns_service_ip   = "172.16.0.10"

  reserved_cidrs = [
    "10.10.0.0/16",
    "10.20.0.0/16",
    "10.30.0.0/16",
    "10.40.0.0/16",
    "10.50.0.0/16",
  ]

  api_server_authorized_cidrs = [
    "181.50.102.191/32",
    "186.112.71.16/32",
    "190.108.77.190/32",
    "200.3.193.225/32",
  ]

  github_organization = "MicroTodoSuite"

  system_node_pool = {
    vm_size   = "Standard_D2s_v5"
    vcpus     = 2
    min_count = 1
    max_count = 3
  }
  regional_vcpu_quota = 6

  cluster_admin_principal_ids = ["66666666-6666-6666-6666-666666666666"]
}

run "dr_root_contract" {
  command = plan

  assert {
    condition = toset(keys(output.foundation_contract_data)) == toset([
      "subscription_id",
      "location",
      "kubernetes_version",
      "network_policy_engine",
      "api_server_authorized_cidrs",
      "network",
      "reserved_cidrs",
      "key_vault_name",
      "key_vault_secret_names",
      "key_vault_reader_subjects",
      "github_seed_subjects",
      "ingress",
      "active_active_enabled",
    ])
    error_message = "The root's foundation contract must expose exactly the reviewed non-secret fields and nothing else."
  }

  # Identity of the target: the verified subscription and location.

  assert {
    condition     = output.foundation_contract_data.subscription_id == var.subscription_id && output.foundation_contract_data.location == var.location
    error_message = "The root must plan against exactly the verified subscription and location."
  }

  # Cluster, network policy, and allowlist.

  assert {
    condition     = output.foundation_contract_data.kubernetes_version == "1.35" && output.foundation_contract_data.network_policy_engine == "azure-cni-overlay-cilium"
    error_message = "The DR cluster must run Kubernetes 1.35 with Azure CNI Overlay and Cilium (spec 009 data-model network_policy_engine)."
  }

  assert {
    condition = toset(output.foundation_contract_data.api_server_authorized_cidrs) == toset([
      "181.50.102.191/32",
      "186.112.71.16/32",
      "190.108.77.190/32",
      "200.3.193.225/32",
    ])
    error_message = "The API server allowlist must be exactly the four approved operator /32 CIDRs from the environment's .tfvars (spec 009 FR-016)."
  }

  assert {
    condition = output.foundation_contract_data.network == {
      vnet_cidr        = var.vnet_cidr
      node_subnet_cidr = var.node_subnet_cidr
      pod_cidr         = var.pod_cidr
      service_cidr     = var.service_cidr
      dns_service_ip   = var.dns_service_ip
    }
    error_message = "The root must pass exactly the verified VNet, node, pod, service, and DNS ranges to the module."
  }

  assert {
    condition = length(setsubtract(toset([
      "10.10.0.0/16",
      "10.20.0.0/16",
      "10.30.0.0/16",
      "10.40.0.0/16",
      "10.50.0.0/16",
    ]), toset(output.foundation_contract_data.reserved_cidrs))) == 0
    error_message = "Every rebuilt AWS VPC (eco, fstg, fprd, fdev, shd) must be reserved so no Azure range can overlap it (spec 009 FR-008)."
  }

  # Exact, non-secret Key Vault name mapping (spec 009 research decision 14).

  assert {
    condition = output.foundation_contract_data.key_vault_secret_names == {
      "microtodosuite/prod/auth-api-secrets"                    = "microtodosuite-prod-auth-api-secrets"
      "microtodosuite/observability/alertmanager-slack-webhook" = "microtodosuite-observability-alertmanager-slack-webhook"
      "microtodosuite/security/falcosidekick-slack-webhook"     = "microtodosuite-security-falcosidekick-slack-webhook"
      "microtodosuite/observability/grafana-admin"              = "microtodosuite-observability-grafana-admin"
    }
    error_message = "The root must map exactly the four approved AWS Secrets Manager names to their four Azure Key Vault names, by name only."
  }

  assert {
    condition     = output.foundation_contract_data.key_vault_name == output.key_vault_name && output.key_vault_name == "lex-mts-fprd-kv-dr"
    error_message = "The seed workflow's target vault must be the one vault this state creates (spec 009 data-model SecretTransfer.target_vault)."
  }

  # Consumer identities: the in-cluster readers and the GitHub seed.

  assert {
    condition = toset(output.foundation_contract_data.key_vault_reader_subjects) == toset([
      "system:serviceaccount:prod:external-secrets-jwt",
      "system:serviceaccount:security:security-external-secrets-jwt",
      "system:serviceaccount:observability:observability-external-secrets-jwt",
    ])
    error_message = "Only the three External Secrets service accounts that read these secrets on EKS today may read the DR vault."
  }

  assert {
    condition     = toset(output.foundation_contract_data.github_seed_subjects) == toset(["repo:MicroTodoSuite/.github:environment:azure-dr"])
    error_message = "Only the approved azure-dr environment of the organization's shared .github repository may seed the vault; it matches the AWS DR seed role's subject."
  }

  assert {
    condition     = output.key_vault_reader_client_id != null && output.key_vault_reader_client_id != "" && output.github_seed_client_id != null && output.github_seed_client_id != ""
    error_message = "The root must output the reader and seed client IDs; the workload annotation and the seed workflow consume them."
  }

  assert {
    condition     = output.github_seed_client_id != output.key_vault_reader_client_id
    error_message = "The seed and reader must be distinct identities; the workload never gains write access and the seed never runs in-cluster."
  }

  # Static ingress address consumed by GitOps (T129) and DNS (T134).

  assert {
    condition = output.foundation_contract_data.ingress == {
      public_ip_name      = output.ingress_public_ip_name
      resource_group_name = output.ingress_public_ip_resource_group_name
      endpoint            = output.ingress_public_ip_endpoint
      dns_name            = output.ingress_public_ip_dns_name
    }
    error_message = "The root must output the ingress public IP's name, resource group, address, and DNS name (FQDN), and carry the same values in its contract."
  }

  assert {
    condition     = output.ingress_public_ip_name == "lex-mts-fprd-pip-ingress" && output.ingress_public_ip_resource_group_name == "lex-mts-fprd-rg-ingress"
    error_message = "The ingress address must keep its reviewed name and dedicated resource group; the Istio Service annotations bind to them."
  }

  assert {
    condition     = output.cluster_name == "lex-mts-fprd-aks-dr"
    error_message = "The DR cluster must keep its MTS-IAC-101 name."
  }

  # Active-active stays off (constitution principle 12, spec 009 FR-046).

  assert {
    condition     = var.enable_active_active == false && output.foundation_contract_data.active_active_enabled == false
    error_message = "Active-active routing must be disabled by default."
  }
}

run "rejects_active_active" {
  command = plan

  variables {
    enable_active_active = true
  }

  expect_failures = [var.enable_active_active]
}

run "rejects_a_fifth_allowlist_cidr" {
  command = plan

  variables {
    api_server_authorized_cidrs = [
      "181.50.102.191/32",
      "186.112.71.16/32",
      "190.108.77.190/32",
      "200.3.193.225/32",
      "198.51.100.7/32",
    ]
  }

  expect_failures = [var.api_server_authorized_cidrs]
}

run "rejects_another_environment" {
  command = plan

  variables {
    environment = "fstg"
  }

  expect_failures = [var.environment]
}

run "rejects_an_empty_reserved_set" {
  command = plan

  variables {
    reserved_cidrs = []
  }

  expect_failures = [var.reserved_cidrs]
}
