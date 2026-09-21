# Names built from the governance prefix (PC-IAC-025, MTS-IAC-101), the tags
# every resource carries, and the fixed disaster-recovery identity contract.
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  compact_prefix    = "${var.client}${var.project}${var.environment}"

  names = {
    resource_group            = "${local.governance_prefix}-rg-dr"
    ingress_resource_group    = "${local.governance_prefix}-rg-ingress"
    virtual_network           = "${local.governance_prefix}-vnet-dr"
    node_subnet               = "${local.governance_prefix}-snet-nodes"
    cluster                   = "${local.governance_prefix}-aks-dr"
    cluster_identity          = "${local.governance_prefix}-id-aks"
    kubelet_identity          = "${local.governance_prefix}-id-kubelet"
    key_vault                 = "${local.governance_prefix}-kv-dr"
    key_vault_reader_identity = "${local.governance_prefix}-id-kvreader"
    github_seed_identity      = "${local.governance_prefix}-id-drseed"
    github_seed_role          = "${local.governance_prefix}-role-drseed"
    container_registry        = "${local.compact_prefix}acrdr"
    storage_account           = "${local.compact_prefix}stbackup"
    ingress_public_ip         = "${local.governance_prefix}-pip-ingress"
  }

  ingress_dns_label = "${local.governance_prefix}-dr"

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = "infrastructure"
    CostCenter  = "mts-full"
    ManagedBy   = "terraform"
    Repository  = "microservice-app-ops"
  }

  # The four approved AWS Secrets Manager names and the Azure Key Vault names
  # the seed workflow writes them to (spec 009 research decision 14). Names
  # only: no value ever passes through Terraform.
  key_vault_secret_names = {
    "microtodosuite/prod/auth-api-secrets"                    = "microtodosuite-prod-auth-api-secrets"
    "microtodosuite/observability/alertmanager-slack-webhook" = "microtodosuite-observability-alertmanager-slack-webhook"
    "microtodosuite/security/falcosidekick-slack-webhook"     = "microtodosuite-security-falcosidekick-slack-webhook"
    "microtodosuite/observability/grafana-admin"              = "microtodosuite-observability-grafana-admin"
  }

  # The External Secrets service accounts that read these secrets on EKS
  # today; the AKS secret-store overlay (T129) uses the same accounts.
  key_vault_reader_service_accounts = {
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

  # The same subject the AWS DR seed role trusts: the approved azure-dr
  # environment of the organization's shared .github repository.
  github_seed_subjects = ["repo:${var.github_organization}/.github:environment:azure-dr"]
}
