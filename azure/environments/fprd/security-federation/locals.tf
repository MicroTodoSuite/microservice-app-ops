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

  # The service account the AKS production secret store authenticates as
  # (gitops environments/profiles/full/destinations/aks-dr). The T179 minimum
  # inventory runs no Falco or observability stack on AKS, so their readers
  # are not federated until those capabilities return.
  reader_service_accounts = {
    prod = {
      namespace = "microtodo-prod"
      name      = "external-secrets-jwt"
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
