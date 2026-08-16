locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  neutral_ecr_repository_arns = sort([
    for service in var.neutral_service_names :
    "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${var.expected_account_id}:repository/${var.project}/${service}"
  ])
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = "github-actions"
  })
}

resource "aws_iam_role" "github_ecr_publisher" {
  name                 = "microtodosuite-github-ecr-publisher"
  description          = "Publish reviewed main artifacts only to neutral MicroTodoSuite ECR repositories"
  permissions_boundary = var.iam_permissions_boundary_arn
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactReviewedMainWorkflows"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
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

resource "aws_iam_role_policy" "github_ecr_publisher" {
  name = "publish-neutral-ecr-artifacts"
  role = aws_iam_role.github_ecr_publisher.id
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
