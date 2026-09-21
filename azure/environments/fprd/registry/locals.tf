# Names built from the governance prefix (PC-IAC-025) and the registry's
# configuration (PC-IAC-021).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  compact_prefix    = "${var.client}${var.project}${var.environment}"

  # The governance tags come from each module; these complete PC-IAC-004.
  additional_tags = {
    Owner      = "infrastructure"
    CostCenter = "mts-full"
    Repository = "microservice-app-ops"
  }

  resource_group = {
    name     = "${local.governance_prefix}-rg-registry"
    location = var.location
  }

  container_registry = {
    name                = "${local.compact_prefix}acrdr"
    resource_group_name = module.resource_group.resource_group_name
    location            = var.location
    sku                 = "Standard"
  }
}
