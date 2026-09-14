# Names, access, add-ons, and tags of the fprd/workload root, built here and nowhere else
# (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  cluster_name         = "${local.governance_prefix}-eks-main"
  node_group_name      = "${local.governance_prefix}-ng-bootstrap"
  launch_template_name = "${local.governance_prefix}-lt-bootstrap"

  # The names fprd/networking and fprd/security gave what this root reads.
  vpc_name                    = "${local.governance_prefix}-vpc-main"
  cluster_security_group_name = "${local.governance_prefix}-sg-cluster"
  node_security_group_name    = "${local.governance_prefix}-sg-node"
  cluster_role_name           = "${local.governance_prefix}-role-cluster"
  node_role_name              = "${local.governance_prefix}-role-node"
  addon_role_names            = { vpccni = "${local.governance_prefix}-role-vpccni", ebscsi = "${local.governance_prefix}-role-ebscsi" }
  secrets_key_name            = "${local.governance_prefix}-kms-eks"
  logs_key_name               = "${local.governance_prefix}-kms-ekslogs"

  # The API stays private unless an operator address is named.
  endpoint_public_access = length(var.endpoint_public_access_cidrs) > 0

  control_plane_log_group = {
    standard_name     = "${local.governance_prefix}-cwl-eks"
    retention_in_days = var.control_plane_log_retention_in_days
    kms_key_arn       = data.aws_kms_alias.logs.target_key_arn
  }

  # Keyed by ARN, as the legacy root was, so reordering the list replaces nothing.
  access_entries = {
    for arn in var.cluster_admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        cluster_admin = { policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
      }
    }
  }

  # The AWS add-ons that call AWS take fprd/security's Pod Identity roles, so the CNI is
  # authorized on the first node without an OIDC provider; the agent installs with the
  # cluster. The CNI keeps the legacy settings: network policy enforcement, and prefix
  # delegation for pod density on the bootstrap nodes.
  addons = {
    eks-pod-identity-agent = { addon_version = var.addon_versions.pod_identity_agent, before_compute = true }
    vpc-cni = {
      addon_version             = var.addon_versions.vpc_cni
      before_compute            = true
      pod_identity_associations = { aws-node = data.aws_iam_role.addon["vpccni"].arn }
      configuration_values      = jsonencode({ enableNetworkPolicy = "true", env = { ENABLE_PREFIX_DELEGATION = "true" } })
    }
    kube-proxy = { addon_version = var.addon_versions.kube_proxy, before_compute = true }
    coredns    = { addon_version = var.addon_versions.coredns }
    aws-ebs-csi-driver = {
      addon_version             = var.addon_versions.aws_ebs_csi_driver
      pod_identity_associations = { ebs-csi-controller-sa = data.aws_iam_role.addon["ebscsi"].arn }
    }
  }

  node_labels = { "microtodosuite.io/capacity-owner" = "managed-node-group" }

  # The Karpenter prerequisites this domain owns (PC-IAC-022): the interruption queue the
  # controller polls and the five EventBridge rules that write to it. The controller's identity
  # belongs to the IRSA pass, and its NodePools and EC2NodeClasses to GitOps. Karpenter's
  # reference template keeps a message for 300 seconds, because an interruption notice is
  # worthless once the instance is gone, and the queue carries notices rather than secrets, so it
  # takes SQS-managed encryption instead of a customer key of its own.
  karpenter_queue = {
    name                      = "${local.governance_prefix}-sqs-karpenter"
    message_retention_seconds = 300
    kms_key_arn               = ""
  }

  karpenter_rule_names = {
    scheduled_change      = "${local.governance_prefix}-evr-karpsched"
    spot_interruption     = "${local.governance_prefix}-evr-karpspot"
    rebalance             = "${local.governance_prefix}-evr-karprebal"
    instance_state_change = "${local.governance_prefix}-evr-karpstate"
    capacity_reservation  = "${local.governance_prefix}-evr-karpcapres"
  }

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repository  = var.repository
  }
}
