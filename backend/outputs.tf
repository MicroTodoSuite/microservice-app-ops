output "resource_group_name" {
  value = azurerm_resource_group.terraform_state.name
}

output "storage_account_name" {
  value = azurerm_storage_account.terraform_state.name
}

output "container_name" {
  value = azurerm_storage_container.terraform_state.name
}

output "access_key" {
  value     = azurerm_storage_account.terraform_state.primary_access_key
  sensitive = true
}