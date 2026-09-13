# The shd/security root: the account's GitHub OIDC trust, the role that publishes service
# images, and the key and role every environment's VPC flow logs use (PC-IAC-022). The
# deploy role and the Kyverno image verifier follow in their own changes.

# The GitHub OIDC provider already exists in the account; it is adopted, not created
# (ops spec 004 T010).
import {
  to = module.github_oidc.aws_iam_openid_connect_provider.this
  id = "arn:${local.partition}:iam::${var.aws_account_id}:oidc-provider/${local.github_oidc_host}"
}

module "github_oidc" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-oidc-provider?ref=iam-oidc-provider-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client        = var.client
  project       = var.project
  environment   = var.environment
  url           = "https://${local.github_oidc_host}"
  client_ids    = ["sts.amazonaws.com"]
  standard_name = local.github_oidc_name
}

module "ecr_publisher_role" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.ecr_publisher_role_name
  description              = "Pushes service images from reviewed main-branch workflows to the shared ECR repositories."
  assume_role_policy       = local.ecr_publisher_trust_policy
  inline_policies          = local.ecr_publisher_policies
  managed_policy_arns      = []
  permissions_boundary_arn = ""
}

module "flow_log_key" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//kms-key?ref=kms-key-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  key_name    = local.flow_log_key_name
  description = "Encrypts the VPC flow-log groups of every environment."
  policy      = local.flow_log_key_policy
}

module "flow_log_role" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.flow_log_role_name
  description              = "Delivers the VPC flow logs of every environment to their CloudWatch Logs groups."
  assume_role_policy       = local.flow_log_trust_policy
  inline_policies          = local.flow_log_policies
  managed_policy_arns      = []
  permissions_boundary_arn = ""
}
