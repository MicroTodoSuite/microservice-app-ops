# Contract of the fprd Azure registry root (gitops
# specs/009-full-platform-rollout US5, T119): the DR container registry that
# receives the mirrored, already-signed images (T131). It is Standard with a
# public endpoint and Entra-only access, by the lead decision recorded in
# terraform-azure-modules docs/iac-exceptions.md, so it takes no firewall
# input. Plans offline against a mock provider; no credential and no Azure call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

variables {
  client          = "lex"
  project         = "mts"
  environment     = "fprd"
  subscription_id = "00000000-0000-0000-0000-00000000d0d0"
  location        = "centralus"
}

run "registry_contract" {
  command = plan

  assert {
    condition     = local.resource_group.name == "lex-mts-fprd-rg-registry" && local.resource_group.location == "centralus"
    error_message = "The registry must live in its own resource group in the verified region."
  }

  assert {
    condition     = local.container_registry.name == "lexmtsfprdacrdr" && local.container_registry.resource_group_name == "lex-mts-fprd-rg-registry" && local.container_registry.sku == "Standard"
    error_message = "The registry must carry its separator-free MTS-IAC-101 name and the Standard SKU the lead decision fixed."
  }

  assert {
    condition     = output.container_registry_name == "lexmtsfprdacrdr"
    error_message = "The root must output the registry name the mirror workflows (T131) target."
  }
}

run "rejects_another_environment" {
  command = plan

  variables {
    environment = "fstg"
  }

  expect_failures = [var.environment]
}
