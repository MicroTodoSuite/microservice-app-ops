# Contract for the economical profile's Azure backup-storage workload root.
# Every run is plan-only against a mocked provider. The production backend is
# never initialized and no Azure API is contacted.

mock_provider "azurerm" {
  alias           = "principal"
  override_during = plan
}

variables {
  client                   = "lex"
  project                  = "mts"
  environment              = "eco"
  subscription_id          = "00000000-0000-0000-0000-00000000e0c0"
  location                 = "centralus"
  account_replication_type = "LRS"
}

run "backup_storage_contract" {
  command = plan

  assert {
    condition = toset(keys(output.backup_storage_contract_data)) == toset([
      "resource_group_name",
      "storage_account_name",
      "storage_account_id",
      "primary_blob_endpoint",
      "account_kind",
      "account_tier",
      "account_replication_type",
      "min_tls_version",
      "https_traffic_only_enabled",
      "shared_access_key_enabled",
      "allow_nested_items_to_be_public",
      "infrastructure_encryption_enabled",
      "cross_tenant_replication_enabled",
      "default_to_oauth_authentication",
      "versioning_enabled",
      "blob_delete_retention_days",
      "container_delete_retention_days",
      "permanent_delete_enabled",
      "containers",
    ])
    error_message = "The workload root must expose exactly the reviewed non-secret backup-storage contract."
  }

  assert {
    condition     = output.backup_storage_contract_data.resource_group_name == "lex-mts-eco-rg-backups"
    error_message = "The Azure backup resource group must keep its reviewed economical-profile name."
  }

  assert {
    condition     = output.backup_storage_contract_data.storage_account_name == "lexmtsecostbackups"
    error_message = "The globally unique storage account candidate must keep the separator-free MTS-IAC-101 name."
  }

  assert {
    condition = (
      output.backup_storage_contract_data.account_kind == "StorageV2" &&
      output.backup_storage_contract_data.account_tier == "Standard" &&
      output.backup_storage_contract_data.account_replication_type == var.account_replication_type
    )
    error_message = "The account must be Standard StorageV2 with redundancy selected through the reviewed input."
  }

  assert {
    condition = (
      output.backup_storage_contract_data.min_tls_version == "TLS1_2" &&
      output.backup_storage_contract_data.https_traffic_only_enabled == true &&
      output.backup_storage_contract_data.shared_access_key_enabled == false &&
      output.backup_storage_contract_data.allow_nested_items_to_be_public == false &&
      output.backup_storage_contract_data.infrastructure_encryption_enabled == true &&
      output.backup_storage_contract_data.cross_tenant_replication_enabled == false &&
      output.backup_storage_contract_data.default_to_oauth_authentication == true
    )
    error_message = "The storage account must enforce TLS, Entra-only authorization, no public blobs, and infrastructure encryption."
  }

  assert {
    condition = (
      output.backup_storage_contract_data.versioning_enabled == true &&
      output.backup_storage_contract_data.blob_delete_retention_days == 30 &&
      output.backup_storage_contract_data.container_delete_retention_days == 30 &&
      output.backup_storage_contract_data.permanent_delete_enabled == false
    )
    error_message = "Blob versions and 30-day soft deletion must protect both blobs and containers without permanent delete."
  }

  assert {
    condition = output.backup_storage_contract_data.containers == {
      "tfstate-replicas" = {
        access_type = "private"
      }
      "velero-eco" = {
        access_type = "private"
      }
    }
    error_message = "The root must create exactly the private state-replica and economical Velero containers."
  }

  assert {
    condition = (
      output.backup_storage_contract_data.storage_account_id != "" &&
      output.backup_storage_contract_data.primary_blob_endpoint != ""
    )
    error_message = "The security root and backup writers need non-empty storage account identifiers."
  }
}

run "rejects_unsupported_replication_type" {
  command = plan

  variables {
    account_replication_type = "PREMIUM"
  }

  expect_failures = [var.account_replication_type]
}
