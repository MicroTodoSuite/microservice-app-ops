# Names, trust and permission policies, and tags of the fprd/security-irsa root, built here and
# nowhere else (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  shared_prefix     = "${var.client}-${var.project}-shd"
  partition         = data.aws_partition.current.partition

  cluster_name         = "${local.governance_prefix}-eks-main"
  oidc_provider_name   = "${local.governance_prefix}-oidc-eks"
  node_role_name       = "${local.governance_prefix}-role-node"
  karpenter_queue_name = "${local.governance_prefix}-sqs-karpenter"
  cluster_arn          = "arn:${local.partition}:eks:${var.aws_region}:${var.aws_account_id}:cluster/${local.cluster_name}"


  # IAM condition keys name the issuer without its scheme.
  oidc_issuer_url  = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
  oidc_issuer_host = trimprefix(local.oidc_issuer_url, "https://")

  # The External Secrets stores of observability and security, and the service accounts the
  # GitOps manifests annotate for them.
  webhook_readers = {
    obssecret = {
      secret_name = "${local.governance_prefix}-sm-slackobs"
      subject     = "system:serviceaccount:observability:observability-external-secrets-jwt"
      description = "Reads only the Alertmanager Slack webhook, for observability/observability-external-secrets-jwt on ${local.cluster_name}."
    }
    secsecret = {
      secret_name = "${local.governance_prefix}-sm-slacksec"
      subject     = "system:serviceaccount:security:security-external-secrets-jwt"
      description = "Reads only the Falcosidekick Slack webhook, for security/security-external-secrets-jwt on ${local.cluster_name}."
    }
  }

  service_repository_arns = sort([
    for key in var.service_image_keys :
    "arn:${local.partition}:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.shared_prefix}-ecr-${key}"
  ])

  ecr_authentication_statement = {
    Sid      = "AuthenticateToEcr"
    Effect   = "Allow"
    Action   = "ecr:GetAuthorizationToken"
    Resource = "*"
  }

  # The Karpenter controller's identity. Its permissions are Karpenter's reference CloudFormation
  # template (karpenter.sh/docs/reference/cloudformation/, read 2026-09-14), whose six managed
  # policies become the eighteen statements of one inline policy, each keeping the reference's
  # own statement identifier: node lifecycle, IAM integration, EKS integration, interruption,
  # zonal shift, and resource discovery. Every scoped statement is confined to this cluster's
  # ownership tag, this region, and this account. The controller passes only the node role the
  # bootstrap group already uses, whose Amazon EKS access entry authorizes the nodes it launches,
  # so the full profile needs no Karpenter node role of its own.
  karpenter_cluster_tag = "kubernetes.io/cluster/${local.cluster_name}"

  karpenter_statements = [
    {
      Sid    = "AllowScopedEC2InstanceAccessActions"
      Effect = "Allow"
      Resource = [
        "arn:${local.partition}:ec2:${var.aws_region}::image/*",
        "arn:${local.partition}:ec2:${var.aws_region}::snapshot/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:security-group/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:subnet/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:capacity-reservation/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:placement-group/*",
      ]
      Action = ["ec2:RunInstances", "ec2:CreateFleet"]
    },
    {
      Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*"
      Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
      Condition = {
        StringEquals = { "aws:ResourceTag/${local.karpenter_cluster_tag}" = "owned" }
        StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid    = "AllowScopedEC2InstanceActionsWithTags"
      Effect = "Allow"
      Resource = [
        "arn:${local.partition}:ec2:${var.aws_region}:*:fleet/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:volume/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:network-interface/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
      ]
      Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.karpenter_cluster_tag}" = "owned"
          "aws:RequestTag/eks:eks-cluster-name"           = local.cluster_name
        }
        StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid    = "AllowScopedResourceCreationTagging"
      Effect = "Allow"
      Resource = [
        "arn:${local.partition}:ec2:${var.aws_region}:*:fleet/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:volume/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:network-interface/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
      ]
      Action = "ec2:CreateTags"
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.karpenter_cluster_tag}" = "owned"
          "aws:RequestTag/eks:eks-cluster-name"           = local.cluster_name
          "ec2:CreateAction"                              = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
        }
        StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid      = "AllowScopedResourceTagging"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*"
      Action   = "ec2:CreateTags"
      Condition = {
        StringEquals                = { "aws:ResourceTag/${local.karpenter_cluster_tag}" = "owned" }
        StringLike                  = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        StringEqualsIfExists        = { "aws:RequestTag/eks:eks-cluster-name" = local.cluster_name }
        "ForAllValues:StringEquals" = { "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"] }
      }
    },
    {
      Sid    = "AllowScopedDeletion"
      Effect = "Allow"
      Resource = [
        "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
        "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
      ]
      Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
      Condition = {
        StringEquals = { "aws:ResourceTag/${local.karpenter_cluster_tag}" = "owned" }
        StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
      }
    },
    {
      Sid       = "AllowPassingInstanceRole"
      Effect    = "Allow"
      Resource  = data.aws_iam_role.node.arn
      Action    = "iam:PassRole"
      Condition = { StringEquals = { "iam:PassedToService" = "ec2.${data.aws_partition.current.dns_suffix}" } }
    },
    {
      Sid      = "AllowScopedInstanceProfileCreationActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:iam::${var.aws_account_id}:instance-profile/*"
      Action   = "iam:CreateInstanceProfile"
      Condition = {
        StringEquals = {
          "aws:RequestTag/${local.karpenter_cluster_tag}" = "owned"
          "aws:RequestTag/eks:eks-cluster-name"           = local.cluster_name
          "aws:RequestTag/topology.kubernetes.io/region"  = var.aws_region
        }
        StringLike = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
      }
    },
    {
      Sid      = "AllowScopedInstanceProfileTagActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:iam::${var.aws_account_id}:instance-profile/*"
      Action   = "iam:TagInstanceProfile"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.karpenter_cluster_tag}" = "owned"
          "aws:ResourceTag/topology.kubernetes.io/region"  = var.aws_region
          "aws:RequestTag/${local.karpenter_cluster_tag}"  = "owned"
          "aws:RequestTag/eks:eks-cluster-name"            = local.cluster_name
          "aws:RequestTag/topology.kubernetes.io/region"   = var.aws_region
        }
        StringLike = {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
        }
      }
    },
    {
      Sid      = "AllowScopedInstanceProfileActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:iam::${var.aws_account_id}:instance-profile/*"
      Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
      Condition = {
        StringEquals = {
          "aws:ResourceTag/${local.karpenter_cluster_tag}" = "owned"
          "aws:ResourceTag/topology.kubernetes.io/region"  = var.aws_region
        }
        StringLike = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
      }
    },
    {
      Sid      = "AllowAPIServerEndpointDiscovery"
      Effect   = "Allow"
      Resource = local.cluster_arn
      Action   = "eks:DescribeCluster"
    },
    {
      Sid      = "AllowInterruptionQueueActions"
      Effect   = "Allow"
      Resource = data.aws_sqs_queue.karpenter_interruption.arn
      Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    },
    {
      Sid       = "AllowZonalShiftStatusReadOnly"
      Effect    = "Allow"
      Resource  = "*"
      Action    = "arc-zonal-shift:GetManagedResource"
      Condition = { StringEquals = { "arc-zonal-shift:ResourceIdentifier" = local.cluster_arn } }
    },
    {
      Sid      = "AllowRegionalReadActions"
      Effect   = "Allow"
      Resource = "*"
      Action = [
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribePlacementGroups",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
      ]
      Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
    },
    {
      Sid      = "AllowSSMReadActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:ssm:${var.aws_region}::parameter/aws/service/*"
      Action   = "ssm:GetParameter"
    },
    {
      Sid      = "AllowPricingReadActions"
      Effect   = "Allow"
      Resource = "*"
      Action   = "pricing:GetProducts"
    },
    {
      Sid      = "AllowUnscopedInstanceProfileListAction"
      Effect   = "Allow"
      Resource = "*"
      Action   = "iam:ListInstanceProfiles"
    },
    {
      Sid      = "AllowInstanceProfileReadActions"
      Effect   = "Allow"
      Resource = "arn:${local.partition}:iam::${var.aws_account_id}:instance-profile/*"
      Action   = "iam:GetInstanceProfile"
    },
  ]

  # Every role admits exactly one service account and grants only what that application
  # reads, as the legacy dev roles did.
  irsa_roles = merge(
    {
      for code, namespace in var.jwt_reader_namespaces : "jwt${code}" => {
        subject     = "system:serviceaccount:${namespace}:external-secrets-jwt"
        description = "Reads only the ${code} JWT signing secret, for ${namespace}/external-secrets-jwt on ${local.cluster_name}."
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Sid      = "ReadExactJwtSecret"
            Effect   = "Allow"
            Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
            Resource = data.aws_secretsmanager_secret.jwt[code].arn
          }]
        })
      }
    },
    {
      for key, reader in local.webhook_readers : key => {
        subject     = reader.subject
        description = reader.description
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Sid      = "ReadExactSlackWebhook"
            Effect   = "Allow"
            Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
            Resource = data.aws_secretsmanager_secret.webhook[key].arn
          }]
        })
      }
    },
    {
      trivyecr = {
        subject     = "system:serviceaccount:security:trivy-operator"
        description = "Pulls the shared service images Trivy Operator scans on ${local.cluster_name}."
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            local.ecr_authentication_statement,
            {
              Sid      = "PullServiceImages"
              Effect   = "Allow"
              Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
              Resource = local.service_repository_arns
            },
          ]
        })
      }
      kyvernoecr = {
        subject     = "system:serviceaccount:kyverno:kyverno-admission-controller"
        description = "Reads the shared service images and their signatures for Kyverno admission on ${local.cluster_name}."
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            local.ecr_authentication_statement,
            {
              Sid      = "ReadServiceImageArtifacts"
              Effect   = "Allow"
              Action   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]
              Resource = local.service_repository_arns
            },
          ]
        })
      }
    },
    {
      karpenter = {
        subject     = "system:serviceaccount:kube-system:karpenter"
        description = "Launches, tags, and reclaims the nodes of ${local.cluster_name}, for kube-system/karpenter."
        policy = jsonencode({
          Version   = "2012-10-17"
          Statement = local.karpenter_statements
        })
      }
    },
  )

  irsa_role_names = { for key in keys(local.irsa_roles) : key => "${local.governance_prefix}-role-${key}" }

  irsa_trust_policies = {
    for key, role in local.irsa_roles : key => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowExactServiceAccount"
        Effect    = "Allow"
        Principal = { Federated = module.eks_oidc.provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
            "${local.oidc_issuer_host}:sub" = role.subject
          }
        }
      }]
    })
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
