# Non-secret identifiers the seed workflow (T131), the Azure secret store
# (T129), and the workload root consume.
output "key_vault_name" {
  description = "Name of the empty DR vault, the seed workflow's only target."
  value       = module.key_vault.key_vault_name
}

output "key_vault_url" {
  description = "Data-plane URL of the DR vault, for the Azure secret store (T129)."
  value       = module.key_vault.key_vault_url
}

output "key_vault_secret_names" {
  description = "The four approved AWS Secrets Manager names mapped to their Key Vault names."
  value       = local.key_vault_secret_names
}

output "github_seed_client_id" {
  description = "Client ID the seed workflow federates to."
  value       = module.seed_identity.identity_client_id
}
