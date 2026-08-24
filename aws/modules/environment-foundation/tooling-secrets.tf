# ---------------------------------------------------------------------------
# Full-profile secret containers and the SonarQube reader (spec 009, T019).
#
# Terraform owns the CONTAINERS and the identities that may read them. Values
# reach AWS only as `ephemeral "random_password"` results passed into the
# write-only `secret_string_wo` argument, paired with a non-secret rotation
# counter. Terraform re-evaluates the ephemeral value during the approved apply
# and persists it in neither the plan nor the state, so incrementing a counter
# is the only thing that rotates a stored secret.
# ---------------------------------------------------------------------------

locals {
  full_profile_secret_names = {
    grafana_admin   = "${var.project}/observability/grafana-admin"
    sonarqube_db    = "${var.project}/tooling/sonarqube-db"
    sonarqube_admin = "${var.project}/tooling/sonarqube-admin"
  }

  create_full_profile_secrets = var.create_shared_resources && var.enable_full_profile_tooling_secrets

  full_profile_secret_arns = {
    for key, name in local.full_profile_secret_names :
    key => "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${var.expected_account_id}:secret:${name}"
  }

  sonarqube_secrets_reader_role_name = "${var.project}-sonarqube-secrets-reader"

  # SonarQube is a single shared tenant in full-dev, so its reader trusts one
  # named issuer rather than the shared multi-issuer set.
  sonarqube_reader_issuer = try(
    var.additional_eks_oidc_issuers[var.sonarqube_reader_issuer_label],
    null,
  )

  create_sonarqube_reader = local.create_full_profile_secrets && local.sonarqube_reader_issuer != null
}

resource "aws_secretsmanager_secret" "tooling" {
  for_each = local.create_full_profile_secrets ? local.full_profile_secret_names : {}

  name                    = each.value
  description             = "Full-profile ${replace(each.key, "_", " ")} credential for MicroTodoSuite. Terraform owns the container; the value is written only through a write-only argument and never appears in plan or state."
  recovery_window_in_days = 30

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = each.value
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "tooling" {
  for_each = local.create_full_profile_secrets ? local.full_profile_secret_names : {}

  secret_id                = aws_secretsmanager_secret.tooling[each.key].id
  secret_string_wo         = var.full_profile_secret_values[each.key]
  secret_string_wo_version = var.full_profile_secret_versions[each.key]
}

resource "aws_iam_role" "sonarqube_secrets_reader" {
  count = local.create_sonarqube_reader ? 1 : 0

  name                 = local.sonarqube_secrets_reader_role_name
  description          = "Read only the SonarQube database and administrator secrets through ${var.sonarqube_service_account_subject}"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactSonarQubeExternalSecretsServiceAccount"
      Effect = "Allow"
      Principal = {
        Federated = local.sonarqube_reader_issuer.provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.sonarqube_reader_issuer.issuer_host}:aud" = "sts.amazonaws.com"
          "${local.sonarqube_reader_issuer.issuer_host}:sub" = var.sonarqube_service_account_subject
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

resource "aws_iam_role_policy" "sonarqube_secrets_reader" {
  count = local.create_sonarqube_reader ? 1 : 0

  name = "read-exact-sonarqube-secrets"
  role = aws_iam_role.sonarqube_secrets_reader[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadExactSonarQubeSecrets"
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
      ]
      Resource = sort([
        local.full_profile_secret_arns.sonarqube_db,
        local.full_profile_secret_arns.sonarqube_admin,
      ])
    }]
  })
}
