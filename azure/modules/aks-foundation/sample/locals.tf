# Names built from the governance prefix (PC-IAC-025) and the tags every
# resource carries.
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  compact_prefix    = "${var.client}${var.project}${var.environment}"

  names = {
    resource_group            = "${local.governance_prefix}-rg-sample"
    ingress_resource_group    = "${local.governance_prefix}-rg-sampleing"
    virtual_network           = "${local.governance_prefix}-vnet-sample"
    node_subnet               = "${local.governance_prefix}-snet-sample"
    cluster                   = "${local.governance_prefix}-aks-sample"
    cluster_identity          = "${local.governance_prefix}-id-sampleaks"
    kubelet_identity          = "${local.governance_prefix}-id-samplekub"
    key_vault                 = "${local.governance_prefix}-kv-sample"
    key_vault_reader_identity = "${local.governance_prefix}-id-samplekvr"
    github_seed_identity      = "${local.governance_prefix}-id-sampleseed"
    github_seed_role          = "${local.governance_prefix}-role-sample"
    container_registry        = "${local.compact_prefix}acrsample"
    storage_account           = "${local.compact_prefix}stsample"
    ingress_public_ip         = "${local.governance_prefix}-pip-sample"
  }

  key_vault_reader_service_accounts = {
    sample = {
      namespace = "sample"
      name      = "external-secrets"
    }
  }

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = "infrastructure"
    CostCenter  = "mts-full"
    ManagedBy   = "terraform"
    Repository  = "microservice-app-ops"
  }
}
