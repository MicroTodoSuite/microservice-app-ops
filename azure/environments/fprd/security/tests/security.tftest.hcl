# Contract of the fprd Azure security root (gitops
# specs/009-full-platform-rollout US5): the empty Key Vault, the cluster and
# kubelet identities with exactly the permissions AKS needs, and the GitHub
# seed identity that alone may write the vault. Plans offline against a mock
# provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# Lookups of the networking and registry roots' resources by standard name.
override_data {
  target = data.azurerm_subnet.nodes
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
  }
}

override_data {
  target = data.azurerm_resource_group.ingress
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-ingress"
  }
}

override_data {
  target = data.azurerm_container_registry.dr
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-registry/providers/Microsoft.ContainerRegistry/registries/lexmtsfprdacrdr"
  }
}

# Computed identifiers of resources this root creates.
override_resource {
  target          = module.resource_group.azurerm_resource_group.this
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security"
  }
}

override_resource {
  target          = module.key_vault.azurerm_key_vault.this
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
  }
}

override_resource {
  target          = module.kubelet_identity.azurerm_user_assigned_identity.this
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
    principal_id = "bbbbbbbb-0000-0000-0000-00000000000b"
    client_id    = "bbbbbbbb-1111-1111-1111-11111111111b"
  }
}

override_resource {
  target          = module.seed_identity.azurerm_user_assigned_identity.this
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-drseed"
    principal_id = "dddddddd-0000-0000-0000-00000000000d"
    client_id    = "dddddddd-1111-1111-1111-11111111111d"
  }
}

variables {
  client          = "lex"
  project         = "mts"
  environment     = "fprd"
  subscription_id = "00000000-0000-0000-0000-00000000d0d0"
  location        = "eastus2"
  operator_cidrs = [
    "181.50.102.191/32",
    "186.112.71.16/32",
    "190.108.77.190/32",
    "200.3.193.225/32",
  ]
  github_organization = "MicroTodoSuite"
}

run "key_vault_contract" {
  command = plan

  assert {
    condition     = local.resource_group.name == "lex-mts-fprd-rg-security" && local.key_vault.name == "lex-mts-fprd-kv-dr" && local.key_vault.resource_group_name == "lex-mts-fprd-rg-security" && local.key_vault.soft_delete_retention_days == 90
    error_message = "The vault must carry its MTS-IAC-101 name in the security resource group with 90 days of soft delete."
  }

  assert {
    condition     = toset(local.key_vault_network_access.allowed_ip_cidrs) == toset(var.operator_cidrs) && local.key_vault_network_access.allowed_subnet_ids == ["/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"]
    error_message = "The vault firewall must admit exactly the four operator addresses and the node subnet."
  }

  assert {
    condition = local.key_vault_secret_names == {
      "microtodosuite/prod/auth-api-secrets"                    = "microtodosuite-prod-auth-api-secrets"
      "microtodosuite/observability/alertmanager-slack-webhook" = "microtodosuite-observability-alertmanager-slack-webhook"
      "microtodosuite/security/falcosidekick-slack-webhook"     = "microtodosuite-security-falcosidekick-slack-webhook"
      "microtodosuite/observability/grafana-admin"              = "microtodosuite-observability-grafana-admin"
    }
    error_message = "The root must map exactly the four approved AWS Secrets Manager names to their Key Vault names, by name only (spec 009 research decision 14)."
  }

  assert {
    condition     = output.key_vault_name == "lex-mts-fprd-kv-dr" && output.key_vault_secret_names == local.key_vault_secret_names
    error_message = "The root must output the vault name and the name mapping the seed workflow uses."
  }
}

run "cluster_identity_contract" {
  command = plan

  assert {
    condition     = local.identities.cluster.name == "lex-mts-fprd-id-aks" && local.identities.kubelet.name == "lex-mts-fprd-id-kubelet" && local.identities.seed.name == "lex-mts-fprd-id-drseed"
    error_message = "The identities must carry their MTS-IAC-101 names."
  }

  assert {
    condition = local.cluster_identity_role_assignments == {
      node_subnet = {
        scope                = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-network/providers/Microsoft.Network/virtualNetworks/lex-mts-fprd-vnet-dr/subnets/lex-mts-fprd-snet-nodes"
        role_definition_name = "Network Contributor"
      }
      ingress = {
        scope                = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-ingress"
        role_definition_name = "Network Contributor"
      }
      kubelet_operator = {
        scope                = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.ManagedIdentity/userAssignedIdentities/lex-mts-fprd-id-kubelet"
        role_definition_name = "Managed Identity Operator"
      }
    }
    error_message = "The cluster identity must hold exactly Network Contributor on the node subnet and the ingress resource group, and Managed Identity Operator on the kubelet identity."
  }

  assert {
    condition = local.kubelet_role_assignments == {
      registry = {
        scope                = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-registry/providers/Microsoft.ContainerRegistry/registries/lexmtsfprdacrdr"
        role_definition_name = "AcrPull"
      }
    }
    error_message = "The kubelet identity must hold only AcrPull on the DR registry."
  }
}

run "seed_identity_contract" {
  command = plan

  assert {
    condition = local.seed_federated_credentials == {
      azuredr = {
        name    = "github-azure-dr"
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:MicroTodoSuite/.github:environment:azure-dr"
      }
    }
    error_message = "Only the approved azure-dr environment of the organization's shared .github repository may federate to the seed identity; it matches the AWS DR seed role's subject."
  }

  assert {
    condition     = local.seed_custom_role.name == "lex-mts-fprd-role-drseed" && local.seed_custom_role.scope == "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security"
    error_message = "The seed role must be defined on the security resource group."
  }

  assert {
    condition     = toset(local.seed_custom_role.data_actions) == toset(["Microsoft.KeyVault/vaults/secrets/getSecret/action", "Microsoft.KeyVault/vaults/secrets/setSecret/action", "Microsoft.KeyVault/vaults/secrets/readMetadata/action"]) && length(local.seed_custom_role.actions) == 0
    error_message = "The seed may only get, set, and read the metadata of secrets; never delete, purge, back up, or restore them."
  }

  assert {
    condition = local.seed_role_assignments == {
      vault = {
        scope           = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
        use_custom_role = true
      }
    }
    error_message = "The seed role must be assigned on the DR vault alone."
  }

  assert {
    condition     = output.github_seed_client_id == "dddddddd-1111-1111-1111-11111111111d"
    error_message = "The root must output the seed client ID the seed workflow federates to."
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
