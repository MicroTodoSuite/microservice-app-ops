# The fprd Azure state backend (gitops specs/009-full-platform-rollout US5): a
# resource group and the encrypted, Entra-only, zone-redundant storage account
# whose tfstate container holds every other Azure root's state.
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

module "state_storage" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//storage-account?ref=storage-account-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  additional_tags = local.additional_tags
  storage_account = local.state_storage
  network_access  = local.state_storage_network_access
  containers      = local.state_containers
}
