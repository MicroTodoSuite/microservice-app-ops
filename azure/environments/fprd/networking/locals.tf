# Names built from the governance prefix (PC-IAC-025) and the network's
# configuration (PC-IAC-021).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  # The governance tags come from each module; these complete PC-IAC-004.
  additional_tags = {
    Owner      = "infrastructure"
    CostCenter = "mts-full"
    Repository = "microservice-app-ops"
  }

  network_resource_group = {
    name     = "${local.governance_prefix}-rg-network"
    location = var.location
  }

  ingress_resource_group = {
    name     = "${local.governance_prefix}-rg-ingress"
    location = var.location
  }

  virtual_network = {
    name                = "${local.governance_prefix}-vnet-dr"
    resource_group_name = module.network_resource_group.resource_group_name
    location            = var.location
    address_space       = var.vnet_cidr
  }

  subnets = {
    nodes = {
      name              = "${local.governance_prefix}-snet-nodes"
      address_prefix    = var.node_subnet_cidr
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
    }
  }

  # Terraform owns the address; the Istio Service selects it by name (T129).
  ingress_public_ip = {
    name                = "${local.governance_prefix}-pip-ingress"
    resource_group_name = module.ingress_resource_group.resource_group_name
    location            = var.location
    domain_name_label   = "${local.governance_prefix}-dr"
  }
}
