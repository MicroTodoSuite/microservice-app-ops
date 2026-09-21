# Contract of the fprd Azure security-federation root (gitops
# specs/009-full-platform-rollout US5): the second security pass, which needs
# the cluster's OIDC issuer and therefore runs after the workload root, as the
# AWS security-irsa roots do. It creates the reader identity that the External
# Secrets service accounts federate to, with read-only access to the DR vault.
# Plans offline against a mock provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# Lookups of the workload and security roots' resources by standard name.
override_data {
  target = data.azurerm_kubernetes_cluster.dr
  values = {
    oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
  }
}

override_data {
  target = data.azurerm_key_vault.dr
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
  }
}

override_resource {
  target          = module.reader_identity.azurerm_user_assigned_identity.this
  override_during = plan
  values = {
    principal_id = "cccccccc-0000-0000-0000-00000000000c"
    client_id    = "cccccccc-1111-1111-1111-11111111111c"
  }
}

variables {
  client          = "lex"
  project         = "mts"
  environment     = "fprd"
  subscription_id = "00000000-0000-0000-0000-00000000d0d0"
  location        = "eastus2"
}

run "reader_identity_contract" {
  command = plan

  assert {
    condition     = local.reader_identity.name == "lex-mts-fprd-id-kvreader" && local.reader_identity.resource_group_name == "lex-mts-fprd-rg-security"
    error_message = "The reader identity must carry its MTS-IAC-101 name in the security resource group."
  }

  assert {
    condition = local.reader_federated_credentials == {
      prod = {
        name    = "kvreader-prod"
        issuer  = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
        subject = "system:serviceaccount:prod:external-secrets-jwt"
      }
      security = {
        name    = "kvreader-security"
        issuer  = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
        subject = "system:serviceaccount:security:security-external-secrets-jwt"
      }
      observability = {
        name    = "kvreader-observability"
        issuer  = "https://eastus2.oic.prod-aks.azure.com/33333333-3333-3333-3333-333333333333/aaaaaaaa-0000-0000-0000-000000000000/"
        subject = "system:serviceaccount:observability:observability-external-secrets-jwt"
      }
    }
    error_message = "Only the three External Secrets service accounts that read these secrets on EKS today may federate, and only through this cluster's OIDC issuer."
  }

  assert {
    condition = local.reader_role_assignments == {
      vault = {
        scope                = "/subscriptions/00000000-0000-0000-0000-00000000d0d0/resourceGroups/lex-mts-fprd-rg-security/providers/Microsoft.KeyVault/vaults/lex-mts-fprd-kv-dr"
        role_definition_name = "Key Vault Secrets User"
      }
    }
    error_message = "The reader must hold only Key Vault Secrets User, on the DR vault alone."
  }

  assert {
    condition     = output.key_vault_reader_client_id == "cccccccc-1111-1111-1111-11111111111c"
    error_message = "The root must output the reader client ID the service accounts' workload-identity annotation carries (T129)."
  }
}

run "rejects_another_subscription" {
  command = plan

  override_data {
    target = data.azurerm_client_config.current
    values = {
      subscription_id = "99999999-9999-9999-9999-999999999999"
    }
  }

  expect_failures = [data.azurerm_client_config.current]
}

run "rejects_another_environment" {
  command = plan

  variables {
    environment = "fstg"
  }

  expect_failures = [var.environment]
}
