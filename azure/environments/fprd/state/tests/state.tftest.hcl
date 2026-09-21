# Contract of the fprd Azure state root (gitops specs/009-full-platform-rollout
# US5): the resource group and the encrypted, Entra-only storage account whose
# tfstate container holds every other Azure root's state. Plans offline
# against a mock provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# Offline placeholders; the operator-owned fprd.tfvars carries the verified
# values (PC-IAC-024).
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
}

run "state_backend_contract" {
  command = plan

  assert {
    condition     = local.resource_group.name == "lex-mts-fprd-rg-state" && local.resource_group.location == "eastus2"
    error_message = "The state resource group must carry its MTS-IAC-101 name in the verified region."
  }

  assert {
    condition     = local.state_storage.name == "lexmtsfprdsttfstate" && local.state_storage.resource_group_name == "lex-mts-fprd-rg-state" && local.state_storage.replication_type == "ZRS"
    error_message = "The state account must carry its separator-free name and survive a zone failure (ZRS)."
  }

  assert {
    condition     = local.state_storage.retention_days >= 30
    error_message = "Deleted state blobs and containers must be kept for at least 30 days."
  }

  assert {
    condition     = toset(local.state_storage_network_access.allowed_ip_addresses) == toset(["181.50.102.191", "186.112.71.16", "190.108.77.190", "200.3.193.225"]) && length(local.state_storage_network_access.allowed_subnet_ids) == 0
    error_message = "The state account firewall must admit exactly the four operator addresses, as plain addresses the storage firewall accepts."
  }

  assert {
    condition     = local.state_containers == { tfstate = { name = "tfstate" } }
    error_message = "The state account must hold exactly one private tfstate container."
  }

  assert {
    condition     = output.storage_account_name == "lexmtsfprdsttfstate" && output.state_container_name == "tfstate" && output.resource_group_name == "lex-mts-fprd-rg-state"
    error_message = "The root must output the backend coordinates every other Azure root's backend file uses."
  }

  assert {
    condition     = local.additional_tags == { Owner = "infrastructure", CostCenter = "mts-full", Repository = "microservice-app-ops" }
    error_message = "Every resource must carry the Owner, CostCenter, and Repository tags besides the governance tags."
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
