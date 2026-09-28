# The fprd Azure network (gitops specs/009-full-platform-rollout US5): the DR
# VNet with one private node subnet, and the static ingress address in its own
# resource group, apart from the AKS-managed node resource group.
module "network_resource_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//resource-group?ref=resource-group-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  additional_tags          = local.additional_tags
  expected_subscription_id = var.subscription_id
  resource_group           = local.network_resource_group
}

module "ingress_resource_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//resource-group?ref=resource-group-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  additional_tags          = local.additional_tags
  expected_subscription_id = var.subscription_id
  resource_group           = local.ingress_resource_group
}

module "network" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//network?ref=network-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  additional_tags = local.additional_tags
  virtual_network = local.virtual_network
  reserved_cidrs  = var.reserved_cidrs
  subnets         = local.subnets
}

module "ingress_public_ip" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//public-ip?ref=public-ip-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  additional_tags = local.additional_tags
  public_ip       = local.ingress_public_ip
}
