resource "aws_secretsmanager_secret" "observability_slack_webhook" {
  name                    = "${var.project}/observability/alertmanager-slack-webhook"
  description             = "Slack incoming-webhook URL for Alertmanager golden-signal alerts on ${local.cluster_name}. Terraform only owns the container; the value is provisioned out-of-band by a human operator."
  recovery_window_in_days = 30

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = "${var.project}/observability/alertmanager-slack-webhook"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "observability_secrets_reader" {
  name                 = "${var.project}-observability-secrets-reader"
  description          = "Read only the Alertmanager Slack webhook through ${var.observability_service_account_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactObservabilityExternalSecretsServiceAccount"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = var.observability_service_account_subject
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

resource "aws_iam_role_policy" "observability_secrets_reader" {
  name = "read-exact-observability-slack-webhook"
  role = aws_iam_role.observability_secrets_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactObservabilitySlackWebhook"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = aws_secretsmanager_secret.observability_slack_webhook.arn
    }]
  })
}
