# Names built from the governance prefix (PC-IAC-025), and every grant this
# root makes, declared here so it can be reviewed in one place (PC-IAC-021).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  compact_prefix    = "${var.client}${var.project}${var.environment}"

  # The governance tags come from each module; these complete PC-IAC-004.
  additional_tags = {
    Owner      = "infrastructure"
    CostCenter = "mts-full"
    Repository = "microservice-app-ops"
  }

  resource_group = {
    name     = "${local.governance_prefix}-rg-security"
    location = var.location
  }

  key_vault = {
    name                       = "${local.governance_prefix}-kv-dr"
    resource_group_name        = module.resource_group.resource_group_name
    location                   = var.location
    soft_delete_retention_days = 90
  }

  key_vault_network_access = {
    allowed_ip_cidrs   = var.operator_cidrs
    allowed_subnet_ids = [data.azurerm_subnet.nodes.id]
  }

  # The four approved AWS Secrets Manager names and the Key Vault names the
  # seed workflow writes them to (spec 009 research decision 14). Names only:
  # no value ever passes through Terraform.
  key_vault_secret_names = {
    "microtodosuite/prod/auth-api-secrets"                    = "microtodosuite-prod-auth-api-secrets"
    "microtodosuite/observability/alertmanager-slack-webhook" = "microtodosuite-observability-alertmanager-slack-webhook"
    "microtodosuite/security/falcosidekick-slack-webhook"     = "microtodosuite-security-falcosidekick-slack-webhook"
    "microtodosuite/observability/grafana-admin"              = "microtodosuite-observability-grafana-admin"
  }

  identities = {
    cluster = {
      name                = "${local.governance_prefix}-id-aks"
      resource_group_name = module.resource_group.resource_group_name
      location            = var.location
    }
    kubelet = {
      name                = "${local.governance_prefix}-id-kubelet"
      resource_group_name = module.resource_group.resource_group_name
      location            = var.location
    }
    seed = {
      name                = "${local.governance_prefix}-id-drseed"
      resource_group_name = module.resource_group.resource_group_name
      location            = var.location
    }
  }

  # AKS needs exactly these: to join the node subnet, to use the ingress
  # address's resource group, and to assign the pre-created kubelet identity.
  cluster_identity_role_assignments = {
    node_subnet = {
      scope                = data.azurerm_subnet.nodes.id
      role_definition_name = "Network Contributor"
    }
    ingress = {
      scope                = data.azurerm_resource_group.ingress.id
      role_definition_name = "Network Contributor"
    }
    kubelet_operator = {
      scope                = module.kubelet_identity.identity_id
      role_definition_name = "Managed Identity Operator"
    }
  }

  kubelet_role_assignments = {
    registry = {
      scope                = data.azurerm_container_registry.dr.id
      role_definition_name = "AcrPull"
    }
  }

  # The same subject the AWS DR seed role trusts: the approved azure-dr
  # environment of the organization's shared .github repository.
  seed_federated_credentials = {
    azuredr = {
      name    = "github-azure-dr"
      issuer  = "https://token.actions.githubusercontent.com"
      subject = "repo:${var.github_organization}/.github:environment:azure-dr"
    }
  }

  seed_custom_role = {
    name    = "${local.governance_prefix}-role-drseed"
    scope   = module.resource_group.resource_group_id
    actions = []
    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action",
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
    ]
  }

  seed_role_assignments = {
    vault = {
      scope           = module.key_vault.key_vault_id
      use_custom_role = true
    }
  }
}
