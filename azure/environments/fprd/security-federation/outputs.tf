# The identity the External Secrets service accounts carry in their
# azure.workload.identity/client-id annotation (T129).
output "key_vault_reader_client_id" {
  description = "Client ID of the vault reader identity."
  value       = module.reader_identity.identity_client_id
}

output "subscription_id" {
  description = "The approved subscription this pass verified before planning."
  value       = data.azurerm_client_config.current.subscription_id
}
