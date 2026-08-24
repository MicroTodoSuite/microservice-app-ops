locals {
  kyverno_ecr_verifier_role_name = "microtodosuite-kyverno-ecr-verifier"
  kyverno_ecr_verifier_role_arn  = one(concat(aws_iam_role.kyverno_ecr_verifier[*].arn, data.aws_iam_role.kyverno_ecr_verifier[*].arn))
}

data "aws_iam_role" "kyverno_ecr_verifier" {
  count = var.create_shared_resources ? 0 : 1

  name = local.kyverno_ecr_verifier_role_name
}

resource "aws_iam_role" "kyverno_ecr_verifier" {
  count = var.create_shared_resources ? 1 : 0

  name                 = local.kyverno_ecr_verifier_role_name
  description          = "Read neutral private ECR artifacts for Kyverno signature admission"
  permissions_boundary = var.iam_permissions_boundary_arn

  # One statement per reviewed cluster issuer. Index 0 is this foundation's own
  # cluster and keeps the original Sid, so a foundation with no additional
  # issuer renders exactly the policy it renders today.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for index, issuer in local.shared_irsa_issuers : {
        Sid    = index == 0 ? "AllowExactKyvernoAdmissionController" : "AllowExactKyvernoAdmissionController${index}"
        Effect = "Allow"
        Principal = {
          Federated = issuer.provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${issuer.issuer_host}:aud" = "sts.amazonaws.com"
            "${issuer.issuer_host}:sub" = var.kyverno_service_account_subject
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

moved {
  from = aws_iam_role.kyverno_ecr_verifier
  to   = aws_iam_role.kyverno_ecr_verifier[0]
}

resource "aws_iam_role_policy" "kyverno_ecr_verifier" {
  count = var.create_shared_resources ? 1 : 0

  name = "verify-neutral-ecr-artifacts"
  role = aws_iam_role.kyverno_ecr_verifier[0].id
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

moved {
  from = aws_iam_role_policy.kyverno_ecr_verifier
  to   = aws_iam_role_policy.kyverno_ecr_verifier[0]
}
