# The fdev/security root, second in the PC-IAC-022 order: the cluster and node roles, the
# Pod Identity roles of the AWS add-ons, the keys for Kubernetes secrets and control-plane
# logs, the extra cluster and node security groups, and the Secrets Manager containers. The
# applications' IRSA roles need the cluster's OIDC issuer and come in the pass after
# fdev/workload.
module "cluster_role" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.cluster_role_name
  description              = "Control-plane role of ${local.cluster_name}."
  assume_role_policy       = local.cluster_trust_policy
  inline_policies          = local.cluster_policies
  managed_policy_arns      = local.cluster_managed_policy_arns
  permissions_boundary_arn = ""
}

module "node_role" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = local.node_role_name
  description              = "Least-privilege role of the ${local.cluster_name} managed nodes: the worker policy and pull-only ECR."
  assume_role_policy       = local.node_trust_policy
  managed_policy_arns      = local.node_managed_policy_arns
  permissions_boundary_arn = ""
}

module "addon_roles" {
  source   = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//iam-role?ref=iam-role-v1.0.0"
  for_each = local.addon_pod_identities

  providers = {
    aws.project = aws.principal
  }

  client                   = var.client
  project                  = var.project
  environment              = var.environment
  role_name                = each.value.role_name
  description              = each.value.description
  assume_role_policy       = local.addon_trust_policies[each.key]
  managed_policy_arns      = [each.value.policy_arn]
  permissions_boundary_arn = ""
}

module "secrets_key" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//kms-key?ref=kms-key-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  key_name    = local.secrets_key_name
  description = "Encrypts the Kubernetes secrets of ${local.cluster_name}."
}

module "logs_key" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//kms-key?ref=kms-key-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  key_name    = local.logs_key_name
  description = "Encrypts the control-plane log group of ${local.cluster_name}."
  policy      = local.logs_key_policy
}

module "cluster_security_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//security-group?ref=security-group-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client              = var.client
  project             = var.project
  environment         = var.environment
  security_group_name = "${local.governance_prefix}-sg-cluster"
  description         = "Extra control-plane security group of ${local.cluster_name}: nodes reach the API on 443."
  vpc_id              = data.aws_vpc.main.id
  ingress_rules       = local.cluster_ingress_rules
}

# The node group's egress to 0.0.0.0/0 is a recorded exception: docs/iac-exceptions.md,
# row "Trivy AWS-0104" for aws/environments/fdev/security.
#trivy:ignore:AVD-AWS-0104
module "node_security_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//security-group?ref=security-group-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client              = var.client
  project             = var.project
  environment         = var.environment
  security_group_name = "${local.governance_prefix}-sg-node"
  description         = "Node security group of ${local.cluster_name}: the control plane, CoreDNS, and node-to-node traffic."
  vpc_id              = data.aws_vpc.main.id
  ingress_rules       = local.node_ingress_rules
  egress_rules        = local.node_egress_rules
  additional_tags     = { "karpenter.sh/discovery" = local.cluster_name }
}

module "jwt_secrets" {
  source   = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//secret?ref=secret-v1.0.0"
  for_each = local.jwt_secret_names

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  secret_name = each.value
  description = "JWT signing secret of the ${each.key} application environment on ${local.cluster_name}. The value is regenerated or copied in the approved cutover, never written by Terraform."
  kms_key_arn = ""
}

module "webhook_secrets" {
  source   = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//secret?ref=secret-v1.0.0"
  for_each = local.webhook_secrets

  providers = {
    aws.project = aws.principal
  }

  client      = var.client
  project     = var.project
  environment = var.environment
  secret_name = each.value.name
  description = each.value.description
  kms_key_arn = ""
}
