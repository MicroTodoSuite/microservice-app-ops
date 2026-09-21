# Names built from the governance prefix (PC-IAC-025) and the reader identity's
# trust and permission (PC-IAC-021).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  # The governance tags come from each module; these complete PC-IAC-004.
  additional_tags = {
    Owner      = "infrastructure"
    CostCenter = "mts-full"
    Repository = "microservice-app-ops"
  }

  reader_identity = {
    name                = "${local.governance_prefix}-id-kvreader"
    resource_group_name = "${local.governance_prefix}-rg-security"
    location            = var.location
  }

  # The External Secrets service accounts that read these secrets on EKS
  # today; the AKS secret-store overlay (T129) uses the same accounts.
  reader_service_accounts = {
    prod = {
      namespace = "prod"
      name      = "external-secrets-jwt"
    }
    security = {
      namespace = "security"
      name      = "security-external-secrets-jwt"
    }
    observability = {
      namespace = "observability"
      name      = "observability-external-secrets-jwt"
    }
  }

  reader_federated_credentials = {
    for key, account in local.reader_service_accounts : key => {
      name    = "kvreader-${key}"
      issuer  = data.azurerm_kubernetes_cluster.dr.oidc_issuer_url
      subject = "system:serviceaccount:${account.namespace}:${account.name}"
    }
  }

  reader_role_assignments = {
    vault = {
      scope                = data.azurerm_key_vault.dr.id
      role_definition_name = "Key Vault Secrets User"
    }
  }
}
