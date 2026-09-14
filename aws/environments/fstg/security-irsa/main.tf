# The fstg/security-irsa root: the second security pass PC-IAC-022 records for IRSA, after
# fstg/workload creates the cluster. It registers the cluster's OIDC issuer in IAM and creates
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
