# Backend coordinates every other fprd Azure root's backend file uses.
output "resource_group_name" {
  description = "Resource group of the state account."
  value       = module.resource_group.resource_group_name
}

output "storage_account_name" {
  description = "Name of the state account."
  value       = module.state_storage.storage_account_name
}

output "state_container_name" {
  description = "Name of the container that holds the fprd Azure roots' state."
  value       = module.state_storage.container_names["tfstate"]
}
