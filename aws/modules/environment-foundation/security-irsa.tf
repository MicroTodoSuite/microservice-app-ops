locals {
  security_slack_webhook_secret_name = "${var.project}/security/falcosidekick-slack-webhook"
  security_slack_webhook_secret_arn = one(concat(
    aws_secretsmanager_secret.security_slack_webhook[*].arn,
    data.aws_secretsmanager_secret.security_slack_webhook[*].arn,
  ))
  security_secrets_reader_role_name = "${var.project}-security-secrets-reader"
  security_secrets_reader_role_arn = one(concat(
    aws_iam_role.security_secrets_reader[*].arn,
    data.aws_iam_role.security_secrets_reader[*].arn,
  ))
}

data "aws_secretsmanager_secret" "security_slack_webhook" {
  count = var.create_shared_resources ? 0 : 1

  name = local.security_slack_webhook_secret_name
}

resource "aws_secretsmanager_secret" "security_slack_webhook" {
  count = var.create_shared_resources ? 1 : 0

  name                    = local.security_slack_webhook_secret_name
  description             = "Slack incoming-webhook URL for Falcosidekick runtime findings on ${local.cluster_name}. Terraform only owns the container; the value is provisioned out-of-band by a human operator."
  recovery_window_in_days = 30

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = local.security_slack_webhook_secret_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

moved {
  from = aws_secretsmanager_secret.security_slack_webhook
  to   = aws_secretsmanager_secret.security_slack_webhook[0]
}

data "aws_iam_role" "security_secrets_reader" {
  count = var.create_shared_resources ? 0 : 1

  name = local.security_secrets_reader_role_name
}

resource "aws_iam_role" "security_secrets_reader" {
  count = var.create_shared_resources ? 1 : 0

  name                 = local.security_secrets_reader_role_name
  description          = "Read only the Falcosidekick Slack webhook through ${var.security_service_account_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  # One statement per reviewed cluster issuer. Index 0 is this foundation's own
  # cluster and keeps the original Sid, so a foundation with no additional
  # issuer renders exactly the policy it renders today.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for index, issuer in local.shared_irsa_issuers : {
        Sid    = index == 0 ? "AllowExactSecurityExternalSecretsServiceAccount" : "AllowExactSecurityExternalSecretsServiceAccount${index}"
        Effect = "Allow"
        Principal = {
          Federated = issuer.provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${issuer.issuer_host}:aud" = "sts.amazonaws.com"
            "${issuer.issuer_host}:sub" = var.security_service_account_subject
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
  from = aws_iam_role.security_secrets_reader
  to   = aws_iam_role.security_secrets_reader[0]
}

resource "aws_iam_role_policy" "security_secrets_reader" {
  count = var.create_shared_resources ? 1 : 0

  name = "read-exact-security-slack-webhook"
  role = aws_iam_role.security_secrets_reader[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactSecuritySlackWebhook"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = aws_secretsmanager_secret.security_slack_webhook[0].arn
    }]
  })
}

moved {
  from = aws_iam_role_policy.security_secrets_reader
  to   = aws_iam_role_policy.security_secrets_reader[0]
}
