# Names, trust and permission policies, and tags of the fdev/security-irsa root, built here and
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
