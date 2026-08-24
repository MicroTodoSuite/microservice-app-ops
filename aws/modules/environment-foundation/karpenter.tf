# ---------------------------------------------------------------------------
# Opt-in full-profile Karpenter prerequisites (spec 009, T018).
#
# Terraform owns only what a cluster cannot bootstrap for itself: the controller
# and node identities, the per-cluster encrypted interruption queue, and the
# EventBridge rules that feed it. GitOps owns the Karpenter controller release
# and every NodePool/EC2NodeClass. Nothing here is created unless
# enable_full_profile_cluster_prerequisites is explicitly enabled.
# ---------------------------------------------------------------------------

locals {
  full_profile_prerequisite_count = var.enable_full_profile_cluster_prerequisites ? 1 : 0
}

resource "aws_kms_key" "karpenter_interruption" {
  count = local.full_profile_prerequisite_count

  description             = "Encrypts the ${local.cluster_name} Karpenter interruption queue"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${var.expected_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEventBridgeToEnqueueInterruptions"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.${data.aws_partition.current.dns_suffix}",
            "sqs.${data.aws_partition.current.dns_suffix}",
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.expected_account_id
          }
        }
      },
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-karpenter-interruption"
  })
}

resource "aws_kms_alias" "karpenter_interruption" {
  count = local.full_profile_prerequisite_count

  name          = "alias/${local.cluster_name}-karpenter-interruption"
  target_key_id = aws_kms_key.karpenter_interruption[0].key_id
}

# The controller trusts this cluster's OIDC provider only. The upstream module
# defaults to an EKS Pod Identity trust; this foundation standardizes on IRSA
# (see the identity_mode contract), so the PodIdentity statement is replaced by
# an exactly-scoped web-identity statement of the same Sid.
data "aws_iam_policy_document" "karpenter_controller_irsa" {
  count = local.full_profile_prerequisite_count

  statement {
    sid     = "PodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = [var.karpenter_service_account_subject]
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.2"

  count = local.full_profile_prerequisite_count

  create       = true
  cluster_name = module.eks.cluster_name
  region       = var.aws_region

  # Controller identity, scoped to this cluster's own OIDC issuer.
  create_iam_role                           = true
  iam_role_name                             = "${local.cluster_name}-karpenter"
  iam_role_use_name_prefix                  = false
  iam_role_description                      = "IRSA role bound exactly to ${var.karpenter_service_account_subject} on ${local.cluster_name}"
  iam_role_permissions_boundary_arn         = var.iam_permissions_boundary_arn
  iam_policy_name                           = "${local.cluster_name}-karpenter"
  iam_policy_use_name_prefix                = false
  iam_role_override_assume_policy_documents = [data.aws_iam_policy_document.karpenter_controller_irsa[0].json]
  create_pod_identity_association           = false
  namespace                                 = "kube-system"
  service_account                           = "karpenter"

  # Per-cluster interruption queue. Queue names are globally unique per account
  # and region, so the cluster-qualified name is what keeps two clusters from
  # consuming each other's interruption events.
  enable_spot_termination                 = true
  queue_name                              = "${local.cluster_name}-karpenter"
  queue_managed_sse_enabled               = false
  queue_kms_master_key_id                 = aws_kms_key.karpenter_interruption[0].arn
  queue_kms_data_key_reuse_period_seconds = 300
  rule_name_prefix                        = "${local.cluster_name}-"

  # Node identity for Karpenter-launched capacity. It mirrors the managed
  # bootstrap node role's least-privilege set: pull-only ECR plus the worker
  # policy, with the CNI policy deliberately left to the vpc-cni IRSA role.
  create_node_iam_role               = true
  node_iam_role_name                 = "${local.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix      = false
  node_iam_role_description          = "Least-privilege role for Karpenter-launched ${local.cluster_name} nodes"
  node_iam_role_permissions_boundary = var.iam_permissions_boundary_arn
  node_iam_role_attach_cni_policy    = false
  node_iam_role_additional_policies = {
    ecr_pull = local.node_managed_policy_arns.ecr_pull
    worker   = local.node_managed_policy_arns.worker
  }
  create_instance_profile = true

  # The node role needs cluster-admin-free API access; the access entry is the
  # supported way to grant a node role its node permissions.
  create_access_entry = true
  access_entry_type   = "EC2_LINUX"
  cluster_ip_family   = "ipv4"

  tags = local.tags
}
