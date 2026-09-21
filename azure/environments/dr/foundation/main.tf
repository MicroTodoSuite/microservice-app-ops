# The Azure disaster-recovery foundation (gitops specs/009-full-platform-rollout
# T126), one call of the aks-foundation module with the verified values.
module "aks_foundation" {
  source = "../../../modules/aks-foundation"

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
  reserved_cidrs                    = var.reserved_cidrs
  vnet_cidr                         = var.vnet_cidr
  node_subnet_cidr                  = var.node_subnet_cidr
  pod_cidr                          = var.pod_cidr
  service_cidr                      = var.service_cidr
  dns_service_ip                    = var.dns_service_ip
  api_server_authorized_ip_ranges   = var.api_server_authorized_cidrs
  key_vault_allowed_cidrs           = var.api_server_authorized_cidrs
  system_node_pool                  = var.system_node_pool
  regional_vcpu_quota               = var.regional_vcpu_quota
  cluster_admin_principal_ids       = var.cluster_admin_principal_ids
  key_vault_reader_service_accounts = local.key_vault_reader_service_accounts
  github_seed_subjects              = local.github_seed_subjects
  ingress_dns_label                 = local.ingress_dns_label
  common_tags                       = local.common_tags
}
