# The empty Key Vault and its two consumers: the in-cluster reader and the
# GitHub seed. No azurerm_key_vault_secret exists here; only the seed workflow
# writes values, and no value ever passes through Terraform.

resource "azurerm_key_vault" "main" {
  provider = azurerm.project

  name                       = var.names.key_vault
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.key_vault_allowed_cidrs
    virtual_network_subnet_ids = [azurerm_subnet.nodes.id]
  }

  tags = merge(local.tags, { Name = var.names.key_vault })

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_user_assigned_identity" "key_vault_reader" {
  provider = azurerm.project

  name                = var.names.key_vault_reader_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.key_vault_reader_identity })
}

resource "azurerm_role_assignment" "key_vault_reader" {
  provider = azurerm.project

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.key_vault_reader.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_federated_identity_credential" "key_vault_reader" {
  provider = azurerm.project
  for_each = var.key_vault_reader_service_accounts

  name                      = "kvreader-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.key_vault_reader.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
}

resource "azurerm_user_assigned_identity" "github_seed" {
  provider = azurerm.project

  name                = var.names.github_seed_identity
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = merge(local.tags, { Name = var.names.github_seed_identity })
}

# The seed may get, set, and read the metadata of secrets, never delete, purge,
# back up, or restore them. A custom role cannot be defined on one resource, so
# it is defined on the resource group and assigned on the vault alone.
resource "azurerm_role_definition" "github_seed" {
  provider = azurerm.project

  name        = var.names.github_seed_role
  scope       = azurerm_resource_group.main.id
  description = "Seed the disaster-recovery Key Vault with the approved secret values; no delete, purge, backup, or restore."

  permissions {
    actions = []
    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action",
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.main.id]
}

resource "azurerm_role_assignment" "github_seed" {
  provider = azurerm.project

  scope              = azurerm_key_vault.main.id
  role_definition_id = azurerm_role_definition.github_seed.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github_seed.principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_federated_identity_credential" "github_seed" {
  provider = azurerm.project
  for_each = var.github_seed_subjects

  name                      = "drseed-${substr(sha256(each.value), 0, 16)}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_seed.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
}
