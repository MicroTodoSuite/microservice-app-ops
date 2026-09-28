# Contract of the fprd Azure networking root (gitops
# specs/009-full-platform-rollout US5, T119): the DR VNet with one private node
# subnet, the Terraform-owned static ingress address in its own resource group,
# and the traffic-routing switch that keeps active-active off. Plans offline
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

# The VNet and node subnet are the maintainer's 2026-09-21 selection, clear of
# every AWS VPC including the 10.50.0.0/16 egress hub. Subscription, location,
# and the DNS label are offline placeholders the DR preflight (T124) verifies.
variables {
  client            = "lex"
  project           = "mts"
  environment       = "fprd"
  subscription_id   = "00000000-0000-0000-0000-00000000d0d0"
  location          = "centralus"
  vnet_cidr         = "10.60.0.0/16"
  node_subnet_cidr  = "10.60.0.0/22"
  reserved_cidrs    = ["10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "10.40.0.0/16", "10.50.0.0/16"]
  ingress_dns_label = "lex-mts-fprd-dr"
}

run "networking_contract" {
  command = plan

  assert {
    condition     = local.network_resource_group.name == "lex-mts-fprd-rg-network" && local.ingress_resource_group.name == "lex-mts-fprd-rg-ingress"
    error_message = "The network and the ingress address must live in their own, separately named resource groups."
  }

  assert {
    condition     = local.virtual_network.name == "lex-mts-fprd-vnet-dr" && local.virtual_network.address_space == "10.60.0.0/16" && local.virtual_network.location == "centralus"
    error_message = "The VNet must carry its MTS-IAC-101 name, the collision-free 10.60.0.0/16 range, and the verified region."
  }

  assert {
    condition     = keys(local.subnets) == ["nodes"] && local.subnets.nodes.name == "lex-mts-fprd-snet-nodes" && local.subnets.nodes.address_prefix == "10.60.0.0/22"
    error_message = "The VNet must hold exactly one node subnet, the first /22 of the VNet."
  }

  assert {
    condition     = toset(local.subnets.nodes.service_endpoints) == toset(["Microsoft.KeyVault", "Microsoft.Storage"])
    error_message = "The node subnet must reach Key Vault and Storage through service endpoints, so both keep denying public access by default."
  }

  assert {
    condition     = local.ingress_public_ip.name == "lex-mts-fprd-pip-ingress" && local.ingress_public_ip.resource_group_name == "lex-mts-fprd-rg-ingress" && local.ingress_public_ip.domain_name_label == "lex-mts-fprd-dr"
    error_message = "The ingress address must keep its reviewed name and resource group and carry the verified DNS label; the Istio Service annotations bind to them (T129)."
  }

  assert {
    condition     = output.virtual_network_name == "lex-mts-fprd-vnet-dr" && output.ingress_public_ip_name == "lex-mts-fprd-pip-ingress" && output.ingress_public_ip_resource_group_name == "lex-mts-fprd-rg-ingress"
    error_message = "The root must output the VNet and the ingress address's name and resource group for GitOps (T129)."
  }

  assert {
    condition     = var.enable_active_active == false && output.traffic_routing_data == { mode = "failover", active_active_enabled = false }
    error_message = "Active-active routing must be disabled by default; eligible traffic reaches Azure only by health-checked failover (constitution principle 12)."
  }
}

run "rejects_active_active" {
  command = plan

  variables {
    enable_active_active = true
  }

  expect_failures = [var.enable_active_active]
}

run "rejects_the_aws_hub_range" {
  command = plan

  variables {
    vnet_cidr        = "10.50.0.0/16"
    node_subnet_cidr = "10.50.0.0/22"
  }

  expect_failures = [var.vnet_cidr]
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
