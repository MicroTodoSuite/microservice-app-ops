# Contract for the identities and container-scoped role assignments used by
# off-provider backups. The mocked provider keeps every run offline and plan-only.

mock_provider "azurerm" {
  alias           = "principal"
  override_during = plan
}

variables {
  client                = "lex"
  project               = "mts"
  environment           = "eco"
  subscription_id       = "00000000-0000-0000-0000-00000000e0c0"
  location              = "centralus"
  velero_principal_id   = "22222222-2222-2222-2222-222222222222"
  resource_group_name   = "lex-mts-eco-rg-backups"
  storage_account_name  = "lexmtsecostbackups"
  state_container_name  = "tfstate-replicas"
  velero_container_name = "velero-eco"
}

run "backup_identity_contract" {
  command = plan

  assert {
    condition     = output.backup_identity_contract_data.replication_identity_name == "lex-mts-eco-id-tfstaterep"
    error_message = "The state-replication managed identity must keep its reviewed MTS-IAC-101 name."
  }

  assert {
    condition = output.backup_identity_contract_data.replication_federated_credentials == {
      "github-offsite-backups" = {
        issuer   = "https://token.actions.githubusercontent.com"
        subject  = "repo:MicroTodoSuite/microservice-app-ops:environment:offsite-backups"
        audience = ["api://AzureADTokenExchange"]
      }
    }
    error_message = "Only the approved GitHub environment may federate into the replication identity."
  }

  assert {
    condition = output.backup_identity_contract_data.role_assignments == {
      "state-replication" = {
        container            = "tfstate-replicas"
        role_definition_name = "Storage Blob Data Contributor"
        principal_id         = output.backup_identity_contract_data.replication_principal_id
      }
      "velero" = {
        container            = "velero-eco"
        role_definition_name = "Storage Blob Data Contributor"
        principal_id         = var.velero_principal_id
      }
    }
    error_message = "Each writer must have Blob Data Contributor on only its own container."
  }

  assert {
    condition     = output.backup_identity_contract_data.replication_client_id != "" && output.backup_identity_contract_data.replication_principal_id != ""
    error_message = "The workflow needs the managed identity client ID and the role assignment needs its principal ID."
  }
}

run "rejects_one_principal_for_both_writers" {
  command = plan

  variables {
    velero_principal_id = "11111111-1111-1111-1111-111111111111"
  }

  expect_failures = [var.velero_principal_id]
}
