data "aws_partition" "current" {}

locals {
  vpc_cni_namespace       = "kube-system"
  vpc_cni_service_account = "aws-node"
  vpc_cni_subject         = "system:serviceaccount:${local.vpc_cni_namespace}:${local.vpc_cni_service_account}"

  ebs_csi_namespace       = "kube-system"
  ebs_csi_service_account = "ebs-csi-controller-sa"
  ebs_csi_subject         = "system:serviceaccount:${local.ebs_csi_namespace}:${local.ebs_csi_service_account}"

  node_managed_policy_arns = {
    ecr_pull = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    worker   = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  }
}

resource "aws_iam_role" "node" {
  name                 = "${local.cluster_name}-node"
  description          = "Limited worker-node role for the ${local.cluster_name} stable bootstrap node group"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEc2AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.${data.aws_partition.current.dns_suffix}"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_managed_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_role" "vpc_cni" {
  name                 = "${local.cluster_name}-vpc-cni"
  description          = "IRSA role bound exactly to ${local.vpc_cni_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowVpcCniWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = local.vpc_cni_subject
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role" "ebs_csi" {
  name                 = "${local.cluster_name}-ebs-csi"
  description          = "IRSA role bound exactly to ${local.ebs_csi_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEbsCsiControllerWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = local.ebs_csi_subject
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# Shared IRSA issuer set (spec 009, T019).
#
# The reader roles below are account singletons, but the full profile runs
# several clusters. Each reviewed extra issuer contributes ONE trust statement
# carrying the same exact audience and service-account subject, so a second
# cluster gains access without a second copy of the role and without the
# subject condition ever widening.
#
# With no additional issuer configured this renders exactly one statement, so
# the applied policies are unchanged.
# ---------------------------------------------------------------------------

locals {
  shared_irsa_issuers = concat(
    [{
      provider_arn = module.eks.oidc_provider_arn
      issuer_host  = module.eks.oidc_provider
    }],
    [
      for label in sort(keys(var.additional_eks_oidc_issuers)) :
      var.additional_eks_oidc_issuers[label]
    ],
  )
}
