# The fprd Azure registry (gitops specs/009-full-platform-rollout US5): the
# container registry the mirror workflows copy the signed service and platform
# graphs into (T131). It is Standard, with a public endpoint and access by
# Entra identity alone, no admin user and no anonymous pull: the lead decision
# recorded in terraform-azure-modules docs/iac-exceptions.md.
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

module "container_registry" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//container-registry?ref=container-registry-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client             = var.client
  project            = var.project
  environment        = var.environment
  additional_tags    = local.additional_tags
  container_registry = local.container_registry
}
