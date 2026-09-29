# The fprd/security-irsa root: the second security pass PC-IAC-022 records for IRSA, after
# fprd/workload creates the cluster. It registers the cluster's OIDC issuer in IAM and creates
# the roles the in-cluster applications assume through their annotated service accounts. The
# directory name is the recorded PC-IAC-022 exception in docs/iac-exceptions.md.
module "eks_oidc" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-oidc-provider?ref=iam-oidc-provider-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client        = var.client
  project       = var.project
  environment   = var.environment
  url           = local.oidc_issuer_url
  client_ids    = ["sts.amazonaws.com"]
  standard_name = local.oidc_provider_name
}

module "irsa_roles" {
  source   = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"
  for_each = local.irsa_roles

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.irsa_role_names[each.key]
  description              = each.value.description
  assume_role_policy       = local.irsa_trust_policies[each.key]
  inline_policies          = { (each.key) = each.value.policy }
  managed_policy_arns      = []
  permissions_boundary_arn = ""
}

# The AKS disaster-recovery cluster's issuer, registered in IAM so its cert-manager can assume
# the AKS DNS-01 role (gitops spec 009 T134). It exists only once the solvers are enabled.
module "aks_oidc" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-oidc-provider?ref=iam-oidc-provider-v1.0.0"
  count  = var.enable_dns01_solvers ? 1 : 0

  providers = {
    aws.project = aws.principal
  }

  client        = var.client
  project       = var.project
  environment   = var.environment
  url           = local.aks_oidc_issuer_url
  client_ids    = local.aks_oidc_client_ids
  standard_name = local.aks_oidc_provider_name
}

module "dns01_roles" {
  source   = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"
  for_each = local.dns01_roles

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.dns01_role_names[each.key]
  description              = each.value.description
  assume_role_policy       = local.dns01_trust_policies[each.key]
  inline_policies          = { (each.key) = each.value.policy }
  managed_policy_arns      = []
  permissions_boundary_arn = ""
}
