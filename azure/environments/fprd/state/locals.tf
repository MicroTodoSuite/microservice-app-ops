# Names built from the governance prefix (PC-IAC-025) and the state backend's
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
    name     = "${local.governance_prefix}-rg-state"
    location = var.location
  }

  state_storage = {
    name                = "${local.compact_prefix}sttfstate"
    resource_group_name = module.resource_group.resource_group_name
    location            = var.location
    replication_type    = "ZRS"
    retention_days      = 30
  }

  # The storage firewall takes plain addresses, not /32 blocks.
  state_storage_network_access = {
    allowed_ip_addresses = [for cidr in var.operator_cidrs : trimsuffix(cidr, "/32")]
    allowed_subnet_ids   = []
  }

  state_containers = {
    tfstate = {
      name = "tfstate"
    }
  }
}
