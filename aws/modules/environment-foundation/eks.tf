locals {
  bootstrap_access_entries = {
    for principal_arn in var.bootstrap_admin_principal_arns : principal_arn => {
      principal_arn = principal_arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access                  = true
  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = sort(tolist(var.cluster_public_access_cidrs))
  authentication_mode                      = "API"
  access_entries                           = local.bootstrap_access_entries
  enable_cluster_creator_admin_permissions = false

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 90

  create_kms_key                  = true
  enable_kms_key_rotation         = true
  kms_key_deletion_window_in_days = 30
  kms_key_description             = "Encrypts Kubernetes secrets for ${local.cluster_name}"
  kms_key_administrators          = sort(tolist(var.bootstrap_admin_principal_arns))
  encryption_config = {
    resources = ["secrets"]
  }

  upgrade_policy = {
    support_type = "STANDARD"
  }

  enable_irsa = true

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = local.tags

  # The module resolves the source IAM role during provisioning. Keep that
  # provider lookup ordered after the fixed cluster-input contract is accepted.
  depends_on = [terraform_data.eks_input_guard]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = local.addon_versions.vpc_cni
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # The v1.23 managed-add-on schema models this boolean as a string. Enabling
  # it makes the aws-network-policy-agent enforce GitOps-owned NetworkPolicy
  # resources while keeping policy manifests outside Terraform ownership.
  #
  # ENABLE_PREFIX_DELEGATION raises max pods per m7i-flex.large node from ~29
  # (one IP per ENI slot) to well over 100 (one /28 prefix per ENI slot). The
  # two-node bootstrap group was already at 52/58 allocatable pod slots before
  # any observability/security workload existed; this is a config-only fix
  # (no additional EC2 spend) instead of raising bootstrap_node_desired_size.
  # Private subnets are /20s, so prefix reservation has no IP exhaustion risk.
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
    }
  })

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

module "bootstrap_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.24.2"

  # The pinned module enforces create-before-destroy for node groups. A unique
  # physical name lets replacements coexist while the logical bootstrap tag and
  # capacity role remain stable.
  name            = "bootstrap"
  use_name_prefix = true

  cluster_name                      = module.eks.cluster_name
  cluster_endpoint                  = module.eks.cluster_endpoint
  cluster_auth_base64               = module.eks.cluster_certificate_authority_data
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_ip_family                 = "ipv4"
  kubernetes_version                = var.kubernetes_version
  subnet_ids                        = module.vpc.private_subnets
  vpc_security_group_ids            = [module.eks.node_security_group_id]
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id

  ami_type                       = "AL2023_x86_64_STANDARD"
  ami_release_version            = var.bootstrap_node_ami_release_version
  use_latest_ami_release_version = false
  capacity_type                  = "ON_DEMAND"
  instance_types                 = var.bootstrap_node_instance_types
  min_size                       = var.bootstrap_node_min_size
  desired_size                   = var.bootstrap_node_desired_size
  max_size                       = var.bootstrap_node_max_size

  create_launch_template     = true
  use_custom_launch_template = true
  launch_template_name       = "${local.cluster_name}-bootstrap"
  key_name                   = null

  block_device_mappings = {
    root = {
      device_name = "/dev/xvda"
      ebs = {
        delete_on_termination = true
        encrypted             = true
        iops                  = 3000
        throughput            = 125
        volume_size           = var.bootstrap_node_volume_size
        volume_type           = "gp3"
      }
    }
  }

  metadata_options = {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  node_repair_config = {
    enabled = true
  }

  update_config = {
    max_unavailable = 1
  }

  create_iam_role            = false
  iam_role_arn               = aws_iam_role.node.arn
  iam_role_attach_cni_policy = false
  create_iam_role_policy     = false

  labels = {
    "microtodosuite.io/capacity-owner" = "managed-node-group"
  }

  tags = local.tags

  depends_on = [
    terraform_data.private_egress_ready,
    aws_eks_addon.vpc_cni,
    aws_iam_role_policy_attachment.node,
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = local.addon_versions.coredns
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = local.tags

  depends_on = [module.bootstrap_node_group]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = local.addon_versions.kube_proxy
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = local.tags

  depends_on = [module.bootstrap_node_group]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = local.addon_versions.ebs_csi
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = local.tags

  depends_on = [
    module.bootstrap_node_group,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
