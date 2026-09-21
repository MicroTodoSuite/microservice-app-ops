# Contract of the fprd Azure networking root (gitops
# specs/009-full-platform-rollout US5): the DR VNet with one private node
# subnet, and the Terraform-owned static ingress address in its own resource
# group. Plans offline against a mock provider; no credential and no Azure
# call.
mock_provider "azurerm" {
  alias = "principal"

  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-00000000d0d0"
      tenant_id       = "33333333-3333-3333-3333-333333333333"
    }
  }
}

# Offline placeholders; T124 selects the real ranges from live evidence and the
# operator-owned fprd.tfvars carries them (PC-IAC-024). None is a selection.
variables {
  client           = "lex"
  project          = "mts"
  environment      = "fprd"
  subscription_id  = "00000000-0000-0000-0000-00000000d0d0"
  location         = "eastus2"
  vnet_cidr        = "10.70.0.0/16"
  node_subnet_cidr = "10.70.0.0/22"
  reserved_cidrs   = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "10.40.0.0/16", "10.50.0.0/16"]
}

run "networking_contract" {
  command = plan

  assert {
    condition     = local.network_resource_group.name == "lex-mts-fprd-rg-network" && local.ingress_resource_group.name == "lex-mts-fprd-rg-ingress"
    error_message = "The network and the ingress address must live in their own, separately named resource groups."
  }

  assert {
    condition     = local.virtual_network.name == "lex-mts-fprd-vnet-dr" && local.virtual_network.address_space == "10.70.0.0/16" && local.virtual_network.location == "eastus2"
    error_message = "The VNet must carry its MTS-IAC-101 name and the verified range and region."
  }

  assert {
    condition     = keys(local.subnets) == ["nodes"] && local.subnets.nodes.name == "lex-mts-fprd-snet-nodes" && local.subnets.nodes.address_prefix == "10.70.0.0/22"
    error_message = "The VNet must hold exactly one node subnet with the verified range."
  }

  assert {
    condition     = toset(local.subnets.nodes.service_endpoints) == toset(["Microsoft.KeyVault", "Microsoft.Storage"])
    error_message = "The node subnet must reach Key Vault and Storage through service endpoints, so both deny public access by default."
  }

  assert {
    condition     = local.ingress_public_ip.name == "lex-mts-fprd-pip-ingress" && local.ingress_public_ip.resource_group_name == "lex-mts-fprd-rg-ingress" && local.ingress_public_ip.domain_name_label == "lex-mts-fprd-dr"
    error_message = "The ingress address must keep its reviewed name, resource group, and DNS label; the Istio Service annotations bind to them."
  }

  assert {
    condition     = local.egress_public_ip.name == "lex-mts-fprd-pip-egress" && local.egress_public_ip.resource_group_name == "lex-mts-fprd-rg-ingress" && local.egress_public_ip.domain_name_label == null
    error_message = "The cluster's static egress address must live beside the ingress address, where the cluster identity already holds Network Contributor, and needs no DNS name."
  }

  assert {
    condition     = output.virtual_network_name == "lex-mts-fprd-vnet-dr" && output.ingress_public_ip_name == "lex-mts-fprd-pip-ingress" && output.ingress_public_ip_resource_group_name == "lex-mts-fprd-rg-ingress"
    error_message = "The root must output the VNet and the ingress address's name and resource group for GitOps (T129)."
  }

  assert {
    condition     = var.enable_active_active == false
    error_message = "Active-active routing must be disabled by default (constitution principle 12)."
  }
}

run "rejects_active_active" {
  command = plan

  variables {
    enable_active_active = true
  }

  expect_failures = [var.enable_active_active]
}

run "rejects_an_empty_reserved_set" {
  command = plan

  variables {
    reserved_cidrs = []
  }

  expect_failures = [var.reserved_cidrs]
}

run "rejects_another_environment" {
  command = plan

  variables {
    environment = "fstg"
  }

  expect_failures = [var.environment]
}
