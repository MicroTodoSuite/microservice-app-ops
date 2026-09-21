# Names built from the governance prefix (PC-IAC-025) and the workload's
# configuration, with the looked-up IDs injected (PC-IAC-021).
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
    name     = "${local.governance_prefix}-rg-workload"
    location = var.location
  }

  cluster = {
    name                = "${local.governance_prefix}-aks-dr"
    resource_group_name = module.resource_group.resource_group_name
    location            = var.location
    kubernetes_version  = "1.35"
  }

  cluster_identities = {
    cluster_identity_id = data.azurerm_user_assigned_identity.cluster.id
    kubelet = {
      id        = data.azurerm_user_assigned_identity.kubelet.id
      client_id = data.azurerm_user_assigned_identity.kubelet.client_id
      object_id = data.azurerm_user_assigned_identity.kubelet.principal_id
    }
  }

  cluster_network = {
    subnet_id      = data.azurerm_subnet.nodes.id
    vnet_cidr      = tolist(data.azurerm_virtual_network.dr.address_space)[0]
    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
    reserved_cidrs = var.reserved_cidrs
  }

  recovery_storage = {
    name                = "${local.compact_prefix}stbackup"
    resource_group_name = module.resource_group.resource_group_name
    location            = var.location
    replication_type    = "LRS"
    retention_days      = 30
  }

  # The storage firewall takes plain addresses, not /32 blocks.
  recovery_storage_network_access = {
    allowed_ip_addresses = [for cidr in var.operator_cidrs : trimsuffix(cidr, "/32")]
    allowed_subnet_ids   = [data.azurerm_subnet.nodes.id]
  }

  recovery_containers = {
    backups = {
      name = "backups"
    }
  }
}
