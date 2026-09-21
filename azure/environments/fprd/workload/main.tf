# The fprd Azure workload (gitops specs/009-full-platform-rollout US5): the AKS
# DR cluster, bound to the networking root's private subnet and the security
# root's identities, and the encrypted recovery storage for the off-provider
# copies constitution principle 12 requires.
module "resource_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//resource-group?ref=resource-group-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  additional_tags          = local.additional_tags
  expected_subscription_id = var.subscription_id
  resource_group           = local.resource_group
}

module "aks_cluster" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//aks-cluster?ref=aks-cluster-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                          = var.client
  project                         = var.project
  environment                     = var.environment
  additional_tags                 = local.additional_tags
  cluster                         = local.cluster
  identities                      = local.cluster_identities
  network                         = local.cluster_network
  api_server_authorized_ip_ranges = var.operator_cidrs
  system_node_pool                = var.system_node_pool
  regional_vcpu_quota             = var.regional_vcpu_quota
  admin_group_object_ids          = var.cluster_admin_group_object_ids
}

module "recovery_storage" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//storage-account?ref=storage-account-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  additional_tags = local.additional_tags
  storage_account = local.recovery_storage
  network_access  = local.recovery_storage_network_access
  containers      = local.recovery_containers
}
