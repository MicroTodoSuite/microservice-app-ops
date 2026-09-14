# Names, policies, and tags of the shd/security root, built here and nowhere else
# (PC-IAC-012, PC-IAC-021, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  partition        = data.aws_partition.current.partition
  github_oidc_host = "token.actions.githubusercontent.com"

  github_oidc_name        = "${local.governance_prefix}-oidc-github"
  ecr_publisher_role_name = "${local.governance_prefix}-role-ecrpublish"
  flow_log_role_name      = "${local.governance_prefix}-role-flowlogs"
  flow_log_key_name       = "${local.governance_prefix}-kms-flowlogs"

  image_publisher_subjects = sort([
    for repository in var.image_publisher_repositories :
    "repo:${var.github_organization}/${repository}:ref:refs/heads/main"
  ])
  service_repository_arns = sort([
    for key in var.service_image_keys :
    "arn:${local.partition}:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.governance_prefix}-ecr-${key}"
  ])
  # Every environment's network module names its flow-log group /aws/vpc-flow-logs/<vpc>.
  flow_log_group_arns = "arn:${local.partition}:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/vpc-flow-logs/*"

  # Only main-branch workflows of the listed repositories, with the STS audience.
  ecr_publisher_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowReviewedMainWorkflows"
      Effect    = "Allow"
      Principal = { Federated = module.github_oidc.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = local.image_publisher_subjects
        }
      }
    }]
  })

  ecr_publisher_policies = {
    publish-service-images = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "AuthenticateToEcr"
          Effect   = "Allow"
          Action   = "ecr:GetAuthorizationToken"
          Resource = "*"
        },
        {
          Sid    = "PublishAndSignServiceImages"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:CompleteLayerUpload",
            "ecr:DescribeImages",
            "ecr:GetDownloadUrlForLayer",
            "ecr:InitiateLayerUpload",
            "ecr:ListImages",
            "ecr:PutImage",
            "ecr:UploadLayerPart",
          ]
          Resource = local.service_repository_arns
        },
      ]
    })
  }

  # The flow-logs service may assume the role only for flow logs of this account, the
  # confused-deputy guard the Amazon VPC user guide recommends.
  flow_log_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowVpcFlowLogsOfThisAccount"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.aws_account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ec2:${var.aws_region}:${var.aws_account_id}:vpc-flow-log/*" }
      }
    }]
  })

  # A caller that writes to a log group encrypted with a customer managed key also needs
  # the key, and only through CloudWatch Logs (kms:ViaService), as the CloudWatch Logs
  # user guide sets out; the role has no read action on the groups.
  flow_log_policies = {
    deliver-vpc-flow-logs = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "WriteVpcFlowLogGroups"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
          ]
          Resource = [local.flow_log_group_arns, "${local.flow_log_group_arns}:*"]
        },
        {
          Sid    = "UseTheFlowLogKeyThroughCloudWatchLogs"
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Describe*",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*",
          ]
          Resource  = module.flow_log_key.key_arn
          Condition = { StringEquals = { "kms:ViaService" = "logs.${var.aws_region}.${data.aws_partition.current.dns_suffix}" } }
        },
      ]
    })
  }

  # The account administers the key; CloudWatch Logs in this region may use it only for
  # the flow-log groups, through the kms:EncryptionContext:aws:logs:arn condition.
  flow_log_key_policy = jsonencode({
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
        Sid       = "AllowCloudWatchLogsForFlowLogGroups"
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
        Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = local.flow_log_group_arns } }
      },
    ]
  })

  # The Terraform deploy role (ops spec 004 plan: create first, retire last). Operators assume
  # it with MFA. PowerUserAccess covers every service but IAM; the inline policy adds IAM only
  # for the project's roles and OIDC providers, and it can never change the deploy role itself.
  project_prefix    = "${var.client}-${var.project}"
  deploy_role_name  = "${local.governance_prefix}-role-tfdeploy"
  deploy_role_arn   = "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.deploy_role_name}"
  project_role_arns = "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.project_prefix}-*"
  project_oidc_provider_arns = sort([
    "arn:${local.partition}:iam::${var.aws_account_id}:oidc-provider/${local.github_oidc_host}",
    "arn:${local.partition}:iam::${var.aws_account_id}:oidc-provider/oidc.eks.${var.aws_region}.${data.aws_partition.current.dns_suffix}/id/*",
  ])

  deploy_role_managed_policy_arns = ["arn:${local.partition}:iam::aws:policy/PowerUserAccess"]

  # The only AWS managed policies the rebuilt roots attach to their roles.
  attachable_managed_policy_arns = sort([
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ])

  deploy_role_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowNamedOperatorsWithMfa"
      Effect    = "Allow"
      Principal = { AWS = sort(var.deploy_role_operator_arns) }
      Action    = "sts:AssumeRole"
      Condition = { Bool = { "aws:MultiFactorAuthPresent" = true } }
    }]
  })

  deploy_role_policies = {
    manage-project-iam = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ManageProjectRoles"
          Effect = "Allow"
          Action = [
            "iam:CreateRole",
            "iam:DeleteRole",
            "iam:DeleteRolePolicy",
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:ListAttachedRolePolicies",
            "iam:ListInstanceProfilesForRole",
            "iam:ListRolePolicies",
            "iam:ListRoleTags",
            "iam:PutRolePolicy",
            "iam:TagRole",
            "iam:UntagRole",
            "iam:UpdateAssumeRolePolicy",
            "iam:UpdateRole",
            "iam:UpdateRoleDescription",
          ]
          Resource = local.project_role_arns
        },
        {
          Sid       = "AttachOnlyTheReviewedManagedPolicies"
          Effect    = "Allow"
          Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
          Resource  = local.project_role_arns
          Condition = { ArnEquals = { "iam:PolicyARN" = local.attachable_managed_policy_arns } }
        },
        {
          Sid    = "ManageProjectOidcProviders"
          Effect = "Allow"
          Action = [
            "iam:AddClientIDToOpenIDConnectProvider",
            "iam:CreateOpenIDConnectProvider",
            "iam:DeleteOpenIDConnectProvider",
            "iam:GetOpenIDConnectProvider",
            "iam:ListOpenIDConnectProviderTags",
            "iam:RemoveClientIDFromOpenIDConnectProvider",
            "iam:TagOpenIDConnectProvider",
            "iam:UntagOpenIDConnectProvider",
            "iam:UpdateOpenIDConnectProviderThumbprint",
          ]
          Resource = local.project_oidc_provider_arns
        },
        {
          Sid      = "ListOidcProviders"
          Effect   = "Allow"
          Action   = "iam:ListOpenIDConnectProviders"
          Resource = "*"
        },
        {
          Sid    = "PassPodIdentityRolesToEks"
          Effect = "Allow"
          Action = "iam:PassRole"
          Resource = sort([
            "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.project_prefix}-*-role-ebscsi",
            "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.project_prefix}-*-role-vpccni",
          ])
          Condition = { StringEquals = { "iam:PassedToService" = "pods.eks.amazonaws.com" } }
        },
        {
          Sid    = "PassClusterNodeAndFlowLogRoles"
          Effect = "Allow"
          Action = "iam:PassRole"
          Resource = sort([
            "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.project_prefix}-*-role-cluster",
            "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.project_prefix}-*-role-node",
            "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.flow_log_role_name}",
          ])
        },
        {
          Sid    = "DenyChangingTheDeployRoleItself"
          Effect = "Deny"
          Action = [
            "iam:AttachRolePolicy",
            "iam:DeleteRole",
            "iam:DeleteRolePermissionsBoundary",
            "iam:DeleteRolePolicy",
            "iam:DetachRolePolicy",
            "iam:PutRolePermissionsBoundary",
            "iam:PutRolePolicy",
            "iam:TagRole",
            "iam:UntagRole",
            "iam:UpdateAssumeRolePolicy",
            "iam:UpdateRole",
            "iam:UpdateRoleDescription",
          ]
          Resource = local.deploy_role_arn
        },
        {
          Sid      = "DenyAssumingProjectRoles"
          Effect   = "Deny"
          Action   = "sts:AssumeRole"
          Resource = local.project_role_arns
        },
      ]
    })
  }

  # CloudTrail data events on the Terraform state bucket (ai-agents specs/001 T043): the trail,
  # its log bucket, and the key that encrypts both. The trail's ARN is built, not read, because
  # the key policy must name the trail before the trail exists.
  state_bucket_name      = "${local.governance_prefix}-s3-tfstate-${var.aws_account_id}"
  cloudtrail_trail_name  = "${local.governance_prefix}-ct-tfstate"
  cloudtrail_bucket_name = "${local.governance_prefix}-s3-cloudtrail"
  cloudtrail_key_name    = "${local.governance_prefix}-kms-cloudtrail"
  cloudtrail_trail_arn   = "arn:${local.partition}:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${local.cloudtrail_trail_name}"
  cloudtrail_principal   = "cloudtrail.${data.aws_partition.current.dns_suffix}"

  # The trailing slash confines the trail to this bucket's objects.
  cloudtrail_object_arn_prefixes = ["${data.aws_s3_bucket.state.arn}/"]

  # A year of access records by default. An old version of a log file, which only an expiry or a
  # delete leaves behind, goes thirty days later.
  cloudtrail_log_retention = {
    current_days    = var.trail_log_retention_in_days
    noncurrent_days = 30
  }

  # The statements the CloudTrail User Guide requires of a trail's key, each confined to the state
  # trail by aws:SourceArn. Readers of the logs get kms:Decrypt in IAM through the account
  # delegation; no service decrypts through this policy, because the log bucket uses no S3 Bucket Key.
  cloudtrail_key_policy = jsonencode({
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
        Sid       = "AllowCloudTrailEncryptLogs"
        Effect    = "Allow"
        Principal = { Service = local.cloudtrail_principal }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.cloudtrail_trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${var.aws_account_id}:trail/*" }
        }
      },
      {
        Sid       = "AllowCloudTrailDescribeKey"
        Effect    = "Allow"
        Principal = { Service = local.cloudtrail_principal }
        Action    = "kms:DescribeKey"
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceArn" = local.cloudtrail_trail_arn } }
      },
    ]
  })

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
