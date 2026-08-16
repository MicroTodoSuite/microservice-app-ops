resource "aws_iam_role" "kyverno_ecr_verifier" {
  name                 = "microtodosuite-kyverno-ecr-verifier"
  description          = "Read neutral private ECR artifacts for Kyverno signature admission"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactKyvernoAdmissionController"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = var.kyverno_service_account_subject
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

resource "aws_iam_role_policy" "kyverno_ecr_verifier" {
  name = "verify-neutral-ecr-artifacts"
  role = aws_iam_role.kyverno_ecr_verifier.id
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
        Sid    = "ReadNeutralArtifacts"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = local.neutral_ecr_repository_arns
      },
    ]
  })
}
