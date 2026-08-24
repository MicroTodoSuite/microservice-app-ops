# ---------------------------------------------------------------------------
# Azure DR secret seed identity (spec 009, T019).
#
# One reviewed workflow copies exactly four AWS secrets into Azure Key Vault so
# a JWT minted on AWS stays valid after a request moves to Azure. This is the
# only identity in the account permitted to read secret VALUES, so its trust
# pins repository, environment AND workflow file, and its policy names the four
# ARNs literally. It stays absent until disaster recovery is approved.
# ---------------------------------------------------------------------------

locals {
  dr_secret_seed_role_name = "${var.project}-github-dr-secret-seed"

  create_dr_secret_seed = var.create_shared_resources && var.enable_dr_secret_seed

  # The four approved sources. The production JWT is copied unchanged so a token
  # remains cryptographically valid across clouds; the other three keep the
  # approved notification and administrator contract.
  dr_secret_seed_secret_names = [
    "${var.project}/prod/auth-api-secrets",
    local.observability_slack_webhook_secret_name,
    local.security_slack_webhook_secret_name,
    local.full_profile_secret_names.grafana_admin,
  ]

  dr_secret_seed_source_arns = sort([
    for name in local.dr_secret_seed_secret_names :
    "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${var.expected_account_id}:secret:${name}"
  ])
}

resource "aws_iam_role" "dr_secret_seed" {
  count = local.create_dr_secret_seed ? 1 : 0

  name                 = local.dr_secret_seed_role_name
  description          = "Copy exactly four approved secrets to Azure Key Vault for disaster recovery"
  permissions_boundary = var.iam_permissions_boundary_arn
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactApprovedSeedWorkflow"
      Effect = "Allow"
      Principal = {
        Federated = local.github_actions_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud"              = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub"              = sort(tolist(var.dr_secret_seed_subjects))
          "${local.github_oidc_host}:job_workflow_ref" = sort(tolist(var.dr_secret_seed_workflow_refs))
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

resource "aws_iam_role_policy" "dr_secret_seed" {
  count = local.create_dr_secret_seed ? 1 : 0

  name = "read-exact-dr-seed-secrets"
  role = aws_iam_role.dr_secret_seed[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactDisasterRecoverySources"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = local.dr_secret_seed_source_arns
    }]
  })
}
