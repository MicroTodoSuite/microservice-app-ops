# Contract of the fprd Azure registry root (gitops
# specs/009-full-platform-rollout US5): the DR container registry that
# receives the mirrored, already-signed images (T131). Plans offline against a
# mock provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# The networking root's egress address, looked up by standard name.
override_data {
  target = data.azurerm_public_ip.egress
  values = {
    ip_address = "203.0.113.20"
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
}

run "registry_contract" {
  command = plan

  assert {
    condition     = local.resource_group.name == "lex-mts-fprd-rg-registry" && local.resource_group.location == "eastus2"
    error_message = "The registry must live in its own resource group in the verified region."
  }

  assert {
    condition     = local.container_registry.name == "lexmtsfprdacrdr" && local.container_registry.resource_group_name == "lex-mts-fprd-rg-registry" && local.container_registry.sku == "Premium"
    error_message = "The registry must carry its separator-free MTS-IAC-101 name and the Premium SKU, the only one with network rules."
  }

  assert {
    condition     = toset(local.container_registry_network_access.allowed_ip_cidrs) == toset(["181.50.102.191/32", "186.112.71.16/32", "190.108.77.190/32", "200.3.193.225/32", "203.0.113.20/32"])
    error_message = "The registry firewall must admit exactly the four operator addresses and the cluster's static egress address."
  }

  assert {
    condition     = output.container_registry_name == "lexmtsfprdacrdr"
    error_message = "The root must output the registry name the mirror workflows (T131) target."
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
