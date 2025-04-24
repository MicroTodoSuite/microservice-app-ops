output "resource_group_name" {
  value = module.resource_group.name
}

output "resource_group_location" {
  value = module.resource_group.location
}

output "container_apps_environment_name" {
  value = module.container_apps_environment.name
}

output "acr_login_server" {
  value = module.container_registry.login_server
}

output "acr_admin_username" {
  value = module.container_registry.admin_username
}

output "acr_admin_password" {
  value = module.container_registry.admin_password
  sensitive = true
}
