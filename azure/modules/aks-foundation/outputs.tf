# Non-secret identifiers the DR root, GitOps (spec 009 T129), the seed and
# mirror workflows (T131), and DNS (T134) consume. No output carries a
# credential or a kubeconfig.

output "resource_group_name" {
  description = "Name of the DR resource group."
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, trusted by workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubernetes_version" {
  description = "Kubernetes version the cluster runs."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

output "api_server_authorized_cidrs" {
  description = "Addresses the API server actually admits, read from the cluster."
  value       = azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges
}

output "key_vault_name" {
  description = "Name of the empty DR Key Vault, the seed workflow's only target."
  value       = azurerm_key_vault.main.name
}

output "key_vault_url" {
  description = "Data-plane URL of the DR Key Vault."
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_reader_client_id" {
  description = "Client ID of the workload identity that reads the vault; the External Secrets service accounts carry it."
  value       = azurerm_user_assigned_identity.key_vault_reader.client_id
}

output "github_seed_client_id" {
  description = "Client ID of the identity the seed workflow federates to."
  value       = azurerm_user_assigned_identity.github_seed.client_id
}

output "container_registry_name" {
  description = "Name of the DR container registry."
  value       = azurerm_container_registry.main.name
}

output "container_registry_endpoint" {
  description = "Login server of the DR container registry."
  value       = azurerm_container_registry.main.login_server
}

output "storage_account_name" {
  description = "Name of the encrypted recovery storage account."
  value       = azurerm_storage_account.backup.name
}

output "ingress_public_ip_name" {
  description = "Name of the static ingress public IP, for the azure-pip-name Service annotation."
  value       = azurerm_public_ip.ingress.name
}

output "ingress_public_ip_resource_group_name" {
  description = "Resource group of the static ingress public IP, for the azure-load-balancer-resource-group Service annotation."
  value       = azurerm_resource_group.ingress.name
}

output "ingress_public_ip_endpoint" {
  description = "IPv4 address of the static ingress public IP."
  value       = azurerm_public_ip.ingress.ip_address
}

output "ingress_public_ip_dns_name" {
  description = "Provider FQDN of the static ingress public IP, the DNS target of full-prod-azure.microtodosuite.online."
  value       = azurerm_public_ip.ingress.fqdn
}
