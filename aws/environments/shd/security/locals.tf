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
