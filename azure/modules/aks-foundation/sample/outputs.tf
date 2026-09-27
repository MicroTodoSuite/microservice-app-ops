# Outputs that prove the sample produced a cluster, a vault, and an address.

output "cluster_name" {
  description = "Name of the sample cluster."
  value       = module.aks_foundation.cluster_name
}

output "key_vault_name" {
  description = "Name of the sample Key Vault."
  value       = module.aks_foundation.key_vault_name
}

output "ingress_public_ip_dns_name" {
  description = "Provider FQDN of the sample ingress address."
  value       = module.aks_foundation.ingress_public_ip_dns_name
}
