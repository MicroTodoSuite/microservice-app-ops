# Names, access, add-ons, and tags of the eco/workload root, built here and nowhere else
# (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  cluster_name         = "${local.governance_prefix}-eks-main"
  node_group_name      = "${local.governance_prefix}-ng-bootstrap"
  launch_template_name = "${local.governance_prefix}-lt-bootstrap"

  # The names eco/networking and eco/security gave what this root reads.
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

  # The AWS add-ons that call AWS take eco/security's Pod Identity roles, so the CNI is
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

  # The economical entry point: one ACM certificate for the production host and every
  # environment's subdomain of it, and the shared load balancer the economical Ingresses create
  # through the AWS Load Balancer Controller. The controller tags that load balancer with the
  # cluster and the IngressGroup, so the root finds it by those tags once it exists.
  ingress_group_name          = "${local.governance_prefix}-alb-main"
  ingress_certificate_name    = "${local.governance_prefix}-acm-ingress"
  ingress_certificate_domains = [var.ingress_host, "*.${var.ingress_host}"]
  ingress_load_balancer_tags = {
    "elbv2.k8s.aws/cluster" = local.cluster_name
    "ingress.k8s.aws/stack" = local.ingress_group_name
  }

  # The host and its wildcard validate through the same record, so one record per distinct
  # name. Domain names are known at plan time; the wildcard is skipped by name.
  certificate_validation_options = {
    for option in flatten(aws_acm_certificate.ingress[*].domain_validation_options) : option.domain_name => option
    if !startswith(option.domain_name, "*.")
  }

  # Address records wait for the verified delegation and for the load balancer; a first
  # bring-up plans none.
  ingress_load_balancer_present = length(data.aws_lbs.ingress.arns) == 1
  ingress_records               = var.public_zone_delegation_verified && local.ingress_load_balancer_present ? toset(local.ingress_certificate_domains) : toset([])

  node_labels = { "microtodosuite.io/capacity-owner" = "managed-node-group" }

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
