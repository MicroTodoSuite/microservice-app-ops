output "id" {
  description = "The ID of the Container App"
  value       = azurerm_container_app.app.id
}

output "name" {
  description = "The name of the Container App"
  value       = azurerm_container_app.app.name
}

output "latest_revision_name" {
  description = "The name of the latest revision"
  value       = azurerm_container_app.app.latest_revision_name
}

output "fqdn" {
  description = "The FQDN of the latest revision"
  value       = length(azurerm_container_app.app.ingress) > 0 ? azurerm_container_app.app.ingress[0].fqdn : null
}