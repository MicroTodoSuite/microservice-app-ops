locals {
  environment_jwt_subjects = {
    for environment in var.shared_environments :
    environment => "system:serviceaccount:microtodo-${environment}:external-secrets-jwt"
  }
}

resource "aws_secretsmanager_secret" "environment_jwt" {
  for_each = var.shared_environments

  name                    = "${var.project}/${each.key}/auth-api-secrets"
  description             = "Environment-local JWT signing secret for MicroTodoSuite ${each.key}"
  recovery_window_in_days = 30

  tags = merge(local.tags, {
    Environment = each.key
    Name        = "${var.project}/${each.key}/auth-api-secrets"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "environment_jwt" {
  for_each = var.shared_environments

  secret_id                = aws_secretsmanager_secret.environment_jwt[each.key].id
  secret_string_wo         = var.environment_jwt_values[each.key]
  secret_string_wo_version = var.environment_jwt_secret_version
}

resource "aws_iam_role" "environment_jwt_reader" {
  for_each = var.shared_environments

  name                 = "${var.project}-${each.key}-jwt-reader"
  description          = "Read only the ${each.key} JWT source secret through external-secrets-jwt"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactExternalSecretsServiceAccount"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = local.environment_jwt_subjects[each.key]
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = each.key
  })
}

resource "aws_iam_role_policy" "environment_jwt_reader" {
  for_each = var.shared_environments

  name = "read-exact-environment-jwt-secret"
  role = aws_iam_role.environment_jwt_reader[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactEnvironmentJwtSecret"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = aws_secretsmanager_secret.environment_jwt[each.key].arn
    }]
  })
}
