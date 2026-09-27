# One call of the module, fed from locals and variables (PC-IAC-026).
module "aks_foundation" {
  source = "../"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                            = var.client
  project                           = var.project
  environment                       = var.environment
  subscription_id                   = var.subscription_id
  location                          = var.location
  names                             = local.names
  kubernetes_version                = "1.35"
  reserved_cidrs                    = var.network.reserved_cidrs
  vnet_cidr                         = var.network.vnet_cidr
  node_subnet_cidr                  = var.network.node_subnet_cidr
  pod_cidr                          = var.network.pod_cidr
  service_cidr                      = var.network.service_cidr
  dns_service_ip                    = var.network.dns_service_ip
  api_server_authorized_ip_ranges   = var.operator_cidrs
  key_vault_allowed_cidrs           = var.operator_cidrs
  system_node_pool                  = var.system_node_pool
  regional_vcpu_quota               = var.regional_vcpu_quota
  cluster_admin_principal_ids       = var.cluster_admin_principal_ids
  key_vault_reader_service_accounts = local.key_vault_reader_service_accounts
  github_seed_subjects              = var.github_seed_subjects
  ingress_dns_label                 = "${local.governance_prefix}-sample"
  common_tags                       = local.common_tags
}
