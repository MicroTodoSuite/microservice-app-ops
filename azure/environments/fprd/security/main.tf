# The fprd Azure security domain (gitops specs/009-full-platform-rollout US5):
# the empty, RBAC-only Key Vault closed to all but the operators and the node
# subnet, and the identities with exactly the grants they need. The reader
# identity follows in security-federation, because it trusts the cluster's
# OIDC issuer, which exists only after the workload root.
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

module "key_vault" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//key-vault?ref=key-vault-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  additional_tags = local.additional_tags
  key_vault       = local.key_vault
  network_access  = local.key_vault_network_access
}

# The identity the nodes pull images as.
module "kubelet_identity" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//managed-identity?ref=managed-identity-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                = var.client
  project               = var.project
  environment           = var.environment
  additional_tags       = local.additional_tags
  identity              = local.identities.kubelet
  federated_credentials = {}
  custom_role           = null
  role_assignments      = local.kubelet_role_assignments
}

# The identity the AKS control plane runs as.
module "cluster_identity" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//managed-identity?ref=managed-identity-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                = var.client
  project               = var.project
  environment           = var.environment
  additional_tags       = local.additional_tags
  identity              = local.identities.cluster
  federated_credentials = {}
  custom_role           = null
  role_assignments      = local.cluster_identity_role_assignments
}

# The only identity that may write the vault: the reviewed seed workflow's.
module "seed_identity" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//managed-identity?ref=managed-identity-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                = var.client
  project               = var.project
  environment           = var.environment
  additional_tags       = local.additional_tags
  identity              = local.identities.seed
  federated_credentials = local.seed_federated_credentials
  custom_role           = local.seed_custom_role
  role_assignments      = local.seed_role_assignments
}
