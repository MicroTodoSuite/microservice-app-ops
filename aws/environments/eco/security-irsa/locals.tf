# Names, trust and permission policies, and tags of the eco/security-irsa root, built here and
# nowhere else (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  shared_prefix     = "${var.client}-${var.project}-shd"
  partition         = data.aws_partition.current.partition

  cluster_name       = "${local.governance_prefix}-eks-main"
  oidc_provider_name = "${local.governance_prefix}-oidc-eks"

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

  # The AWS Load Balancer Controller's identity (ops spec 004 T031, for eco since 2026-09-14). Its permissions are the
  # upstream IAM policy of the release GitOps vendors (kubernetes-sigs/aws-load-balancer-controller
  # v3.5.0, docs/install/iam_policy.json, sha256
  # 16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a), with three changes: each
  # statement has an identifier of its own; resource ARNs name this partition, Region, and account;
  # and every condition that accepted any elbv2.k8s.aws/cluster tag requires this cluster's name,
  # the value the controller writes, so the full clusters sharing the account cannot create, retag,
  # modify, or delete each other's load balancers, target groups, or security groups.
  lb_controller_statements = [
    {
      Sid      = "CreateElasticLoadBalancingServiceLinkedRole"
      Effect   = "Allow"
      Action   = ["iam:CreateServiceLinkedRole"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "iam:AWSServiceName" = "elasticloadbalancing.${data.aws_partition.current.dns_suffix}"
        }
      }
    },
    {
      Sid    = "DescribeNetworkAndLoadBalancers"
      Effect = "Allow"
      Action = [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcPeeringConnections",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeTags",
        "ec2:GetCoipPoolUsage",
        "ec2:DescribeCoipPools",
        "ec2:GetSecurityGroupsForVpc",
        "ec2:DescribeIpamPools",
        "ec2:DescribeRouteTables",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeListenerCertificates",
        "elasticloadbalancing:DescribeSSLPolicies",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeTags",
        "elasticloadbalancing:DescribeTrustStores",
        "elasticloadbalancing:DescribeListenerAttributes",
        "elasticloadbalancing:DescribeCapacityReservation",
      ]
      Resource = "*"
    },
    {
      Sid    = "UseCertificatesFirewallsAndShield"
      Effect = "Allow"
      Action = [
        "cognito-idp:DescribeUserPoolClient",
        "acm:ListCertificates",
        "acm:DescribeCertificate",
        "iam:ListServerCertificates",
        "iam:GetServerCertificate",
        "waf-regional:GetWebACL",
        "waf-regional:GetWebACLForResource",
        "waf-regional:AssociateWebACL",
        "waf-regional:DisassociateWebACL",
        "wafv2:GetWebACL",
        "wafv2:GetWebACLForResource",
        "wafv2:AssociateWebACL",
        "wafv2:DisassociateWebACL",
        "shield:GetSubscriptionState",
        "shield:DescribeProtection",
        "shield:CreateProtection",
        "shield:DeleteProtection",
      ]
      Resource = "*"
    },
    {
      Sid    = "ManageIngressOnSecurityGroups"
      Effect = "Allow"
      Action = [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
      ]
      Resource = "*"
    },
    {
      Sid      = "CreateSecurityGroups"
      Effect   = "Allow"
      Action   = ["ec2:CreateSecurityGroup"]
      Resource = "*"
    },
    {
      Sid      = "TagSecurityGroupsOnCreation"
      Effect   = "Allow"
      Action   = ["ec2:CreateTags"]
      Resource = "arn:${local.partition}:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
      Condition = {
        StringEquals = {
          "ec2:CreateAction"                     = "CreateSecurityGroup"
          "aws:RequestTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "RetagClusterSecurityGroups"
      Effect = "Allow"
      Action = [
        "ec2:CreateTags",
        "ec2:DeleteTags",
      ]
      Resource = "arn:${local.partition}:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*"
      Condition = {
        Null = {
          "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
        }
        StringEquals = {
          "aws:ResourceTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "ManageClusterSecurityGroups"
      Effect = "Allow"
      Action = [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DeleteSecurityGroup",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "CreateClusterLoadBalancersAndTargetGroups"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateTargetGroup",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "ManageListenersAndRules"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:CreateRule",
        "elasticloadbalancing:DeleteRule",
      ]
      Resource = "*"
    },
    {
      Sid    = "RetagClusterLoadBalancersAndTargetGroups"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
      ]
      Resource = [
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/app/*/*",
      ]
      Condition = {
        Null = {
          "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
        }
        StringEquals = {
          "aws:ResourceTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "TagListenersAndRules"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
      ]
      Resource = [
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener/net/*/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener/app/*/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener-rule/net/*/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener-rule/app/*/*/*",
      ]
    },
    {
      Sid    = "ManageClusterLoadBalancersAndTargetGroups"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:SetIpAddressType",
        "elasticloadbalancing:SetSecurityGroups",
        "elasticloadbalancing:SetSubnets",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:ModifyListenerAttributes",
        "elasticloadbalancing:ModifyCapacityReservation",
        "elasticloadbalancing:ModifyIpPools",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "TagLoadBalancersAndTargetGroupsOnCreation"
      Effect = "Allow"
      Action = ["elasticloadbalancing:AddTags"]
      Resource = [
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/net/*/*",
        "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:loadbalancer/app/*/*",
      ]
      Condition = {
        StringEquals = {
          "elasticloadbalancing:CreateAction" = [
            "CreateTargetGroup",
            "CreateLoadBalancer",
          ]
          "aws:RequestTag/elbv2.k8s.aws/cluster" = local.cluster_name
        }
      }
    },
    {
      Sid    = "RegisterTargets"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
      ]
      Resource = "arn:${local.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/*/*"
    },
    {
      Sid    = "ModifyListenersRulesAndWebAcls"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:SetWebAcl",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddListenerCertificates",
        "elasticloadbalancing:RemoveListenerCertificates",
        "elasticloadbalancing:ModifyRule",
        "elasticloadbalancing:SetRulePriorities",
      ]
      Resource = "*"
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
      lbcontrol = {
        subject     = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        description = "Creates and manages the load balancers of ${local.cluster_name}, for kube-system/aws-load-balancer-controller."
        policy = jsonencode({
          Version   = "2012-10-17"
          Statement = local.lb_controller_statements
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
