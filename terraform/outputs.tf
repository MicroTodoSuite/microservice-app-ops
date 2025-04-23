output "resource_group_name" {
  description = "The name of the resource group"
  value       = module.resource_group.name
}

output "acr_login_server" {
  description = "The login server of the Azure Container Registry"
  value       = module.container_registry.login_server
}

output "frontend_url" {
  description = "URL to access the frontend application"
  value       = module.frontend.fqdn
}

output "zipkin_url" {
  description = "URL to access Zipkin monitoring"
  value       = module.zipkin.fqdn
}

output "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = module.container_apps_environment.id
}