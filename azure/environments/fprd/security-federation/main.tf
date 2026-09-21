# The fprd Azure security-federation pass (gitops
# specs/009-full-platform-rollout US5). It runs after the workload root,
# because the reader identity trusts the cluster's OIDC issuer, as the AWS
# security-irsa roots trust their clusters' issuers. The reader can only read
# the DR vault's secrets, and only the three External Secrets service accounts
# can federate to it.
module "reader_identity" {
  source = "git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//managed-identity?ref=managed-identity-v1.0.0"

  providers = {
    azurerm.project = azurerm.principal
  }

  client                = var.client
  project               = var.project
  environment           = var.environment
  additional_tags       = local.additional_tags
  identity              = local.reader_identity
  federated_credentials = local.reader_federated_credentials
  custom_role           = null
  role_assignments      = local.reader_role_assignments
}
