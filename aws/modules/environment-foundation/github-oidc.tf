locals {
  github_oidc_host                 = "token.actions.githubusercontent.com"
  github_ecr_publisher_role_name   = "microtodosuite-github-ecr-publisher"
  github_actions_oidc_provider_arn = one(concat(aws_iam_openid_connect_provider.github_actions[*].arn, data.aws_iam_openid_connect_provider.github_actions[*].arn))
  github_ecr_publisher_role_arn    = one(concat(aws_iam_role.github_ecr_publisher[*].arn, data.aws_iam_role.github_ecr_publisher[*].arn))
  neutral_ecr_repository_arns = sort([
    for service in var.neutral_service_names :
    "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${var.expected_account_id}:repository/${var.project}/${service}"
  ])
}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_shared_resources ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_shared_resources ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = "github-actions"
  })
}

moved {
  from = aws_iam_openid_connect_provider.github_actions
  to   = aws_iam_openid_connect_provider.github_actions[0]
}

data "aws_iam_role" "github_ecr_publisher" {
  count = var.create_shared_resources ? 0 : 1

  name = local.github_ecr_publisher_role_name
}

resource "aws_iam_role" "github_ecr_publisher" {
  count = var.create_shared_resources ? 1 : 0

  name                 = local.github_ecr_publisher_role_name
  description          = "Publish reviewed main artifacts only to neutral MicroTodoSuite ECR repositories"
  permissions_boundary = var.iam_permissions_boundary_arn
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactReviewedMainWorkflows"
      Effect = "Allow"
      Principal = {
        Federated = local.github_actions_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = sort(tolist(var.github_oidc_subjects))
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

moved {
  from = aws_iam_role.github_ecr_publisher
  to   = aws_iam_role.github_ecr_publisher[0]
}

resource "aws_iam_role_policy" "github_ecr_publisher" {
  count = var.create_shared_resources ? 1 : 0

  name = "publish-neutral-ecr-artifacts"
  role = aws_iam_role.github_ecr_publisher[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AuthenticateToEcr"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PublishAndSignNeutralArtifacts"
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
        Resource = local.neutral_ecr_repository_arns
      },
    ]
  })
}

moved {
  from = aws_iam_role_policy.github_ecr_publisher
  to   = aws_iam_role_policy.github_ecr_publisher[0]
}
