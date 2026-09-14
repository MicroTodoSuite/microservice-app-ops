# Names, policies, security group rules, and tags of the fstg/security root, built here and
# nowhere else (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  partition    = data.aws_partition.current.partition
  cluster_name = "${local.governance_prefix}-eks-main"
  vpc_name     = "${local.governance_prefix}-vpc-main"

  cluster_role_name = "${local.governance_prefix}-role-cluster"
  node_role_name    = "${local.governance_prefix}-role-node"
  secrets_key_name  = "${local.governance_prefix}-kms-eks"
  logs_key_name     = "${local.governance_prefix}-kms-ekslogs"

  # Amazon EKS names the control-plane log group itself; fstg/workload creates it first.
  control_plane_log_group_arn = "arn:${local.partition}:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/eks/${local.cluster_name}/cluster"

  cluster_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEksControlPlane"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  node_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEc2Nodes"
      Effect    = "Allow"
      Principal = { Service = "ec2.${data.aws_partition.current.dns_suffix}" }
      Action    = "sts:AssumeRole"
    }]
  })

  cluster_managed_policy_arns = ["arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"]

  # The CNI policy is left to the vpc-cni add-on's own role below, as the legacy nodes had it.
  node_managed_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  ]

  cluster_arn = "arn:${local.partition}:eks:${var.aws_region}:${var.aws_account_id}:cluster/${local.cluster_name}"

  # The AWS add-ons that call AWS APIs take their roles through EKS Pod Identity. It needs no
  # OIDC provider, so the roles exist before the cluster and the CNI is authorized from the
  # first node's boot. Each role gets only its AWS managed policy.
  addon_pod_identities = {
    vpccni = {
      role_name       = "${local.governance_prefix}-role-vpccni"
      namespace       = "kube-system"
      service_account = "aws-node"
      policy_arn      = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
      description     = "Pod Identity role of the vpc-cni add-on, kube-system/aws-node, on ${local.cluster_name}."
    }
    ebscsi = {
      role_name       = "${local.governance_prefix}-role-ebscsi"
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arn      = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      description     = "Pod Identity role of the aws-ebs-csi-driver add-on, kube-system/ebs-csi-controller-sa, on ${local.cluster_name}."
    }
  }

  # EKS Pod Identity assumes the role with session tags; the trust admits only the add-on's
  # own service account in this cluster (EKS user guide, pod-id-role).
  addon_trust_policies = {
    for key, addon in local.addon_pod_identities : key => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowEksPodIdentityForTheAddonServiceAccount"
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks-cluster-arn"            = local.cluster_arn
            "aws:RequestTag/kubernetes-namespace"       = addon.namespace
            "aws:RequestTag/kubernetes-service-account" = addon.service_account
          }
        }
      }]
    })
  }

  # The control plane encrypts and decrypts Kubernetes secrets with the secrets key.
  cluster_policies = {
    use-the-secrets-key = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "EncryptKubernetesSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:ListGrants"]
        Resource = module.secrets_key.key_arn
      }]
    })
  }

  # The account administers the key; CloudWatch Logs in this region may use it only for
  # the cluster's control-plane log group.
  logs_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${var.aws_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsForTheControlPlaneLogGroup"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.${data.aws_partition.current.dns_suffix}" }
        Action = [
          "kms:Decrypt",
          "kms:Describe*",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource  = "*"
        Condition = { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.control_plane_log_group_arn } }
      },
    ]
  })

  # The rules the legacy upstream module gave its extra cluster and node groups, now
  # explicit (terraform-aws-modules/eks/aws 21.24.2 defaults and recommended rules).
  cluster_ingress_rules = {
    nodes-https = { description = "Node groups to the cluster API", ip_protocol = "tcp", from_port = 443, to_port = 443, referenced_security_group_id = module.node_security_group.security_group_id }
  }

  node_ingress_rules = merge(
    {
      for port in [443, 4443, 6443, 8443, 9443, 10250, 10251] : "cluster-${port}" => {
        description                  = port == 10250 ? "Cluster API to the node kubelets" : "Cluster API to node port ${port}, for the API server and admission webhooks"
        ip_protocol                  = "tcp"
        from_port                    = port
        to_port                      = port
        referenced_security_group_id = module.cluster_security_group.security_group_id
      }
    },
    {
      self-dns-tcp       = { description = "Node to node CoreDNS over TCP", ip_protocol = "tcp", from_port = 53, to_port = 53, self = true }
      self-dns-udp       = { description = "Node to node CoreDNS over UDP", ip_protocol = "udp", from_port = 53, to_port = 53, self = true }
      self-ephemeral-tcp = { description = "Node to node traffic on ephemeral ports", ip_protocol = "tcp", from_port = 1025, to_port = 65535, self = true }
    },
  )

  node_egress_rules = {
    all = { description = "Nodes reach ECR, STS, S3, the EKS API, and CloudWatch Logs through the NAT gateways", ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
  }

  jwt_secret_names = { for code in var.jwt_environment_codes : code => "${local.governance_prefix}-sm-jwt${code}" }

  # Secrets whose values a person supplies; Terraform owns only the containers.
  webhook_secrets = {
    slackobs = { name = "${local.governance_prefix}-sm-slackobs", description = "Slack incoming-webhook URL for Alertmanager alerts on ${local.cluster_name}. The value is supplied by a person, never by Terraform." }
    slacksec = { name = "${local.governance_prefix}-sm-slacksec", description = "Slack incoming-webhook URL for Falcosidekick security alerts on ${local.cluster_name}. The value is supplied by a person, never by Terraform." }
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
