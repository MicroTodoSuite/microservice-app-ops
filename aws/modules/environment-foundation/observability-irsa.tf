locals {
  observability_slack_webhook_secret_name = "${var.project}/observability/alertmanager-slack-webhook"
  observability_slack_webhook_secret_arn = one(concat(
    aws_secretsmanager_secret.observability_slack_webhook[*].arn,
    data.aws_secretsmanager_secret.observability_slack_webhook[*].arn,
  ))
  observability_secrets_reader_role_name = "${var.project}-observability-secrets-reader"
  observability_secrets_reader_role_arn = one(concat(
    aws_iam_role.observability_secrets_reader[*].arn,
    data.aws_iam_role.observability_secrets_reader[*].arn,
  ))
}

data "aws_secretsmanager_secret" "observability_slack_webhook" {
  count = var.create_shared_resources ? 0 : 1

  name = local.observability_slack_webhook_secret_name
}

resource "aws_secretsmanager_secret" "observability_slack_webhook" {
  count = var.create_shared_resources ? 1 : 0

  name                    = local.observability_slack_webhook_secret_name
  description             = "Slack incoming-webhook URL for Alertmanager golden-signal alerts on ${local.cluster_name}. Terraform only owns the container; the value is provisioned out-of-band by a human operator."
  recovery_window_in_days = 30

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = local.observability_slack_webhook_secret_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

moved {
  from = aws_secretsmanager_secret.observability_slack_webhook
  to   = aws_secretsmanager_secret.observability_slack_webhook[0]
}

data "aws_iam_role" "observability_secrets_reader" {
  count = var.create_shared_resources ? 0 : 1

  name = local.observability_secrets_reader_role_name
}

resource "aws_iam_role" "observability_secrets_reader" {
  count = var.create_shared_resources ? 1 : 0

  name                 = local.observability_secrets_reader_role_name
  description          = "Read only the Alertmanager Slack webhook through ${var.observability_service_account_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  # One statement per reviewed cluster issuer. Index 0 is this foundation's own
  # cluster and keeps the original Sid, so a foundation with no additional
  # issuer renders exactly the policy it renders today.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for index, issuer in local.shared_irsa_issuers : {
        Sid    = index == 0 ? "AllowExactObservabilityExternalSecretsServiceAccount" : "AllowExactObservabilityExternalSecretsServiceAccount${index}"
        Effect = "Allow"
        Principal = {
          Federated = issuer.provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${issuer.issuer_host}:aud" = "sts.amazonaws.com"
            "${issuer.issuer_host}:sub" = var.observability_service_account_subject
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
  from = aws_iam_role.observability_secrets_reader
  to   = aws_iam_role.observability_secrets_reader[0]
}

resource "aws_iam_role_policy" "observability_secrets_reader" {
  count = var.create_shared_resources ? 1 : 0

  name = "read-exact-observability-slack-webhook"
  role = aws_iam_role.observability_secrets_reader[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactObservabilitySlackWebhook"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = aws_secretsmanager_secret.observability_slack_webhook[0].arn
    }]
  })
}

moved {
  from = aws_iam_role_policy.observability_secrets_reader
  to   = aws_iam_role_policy.observability_secrets_reader[0]
}
