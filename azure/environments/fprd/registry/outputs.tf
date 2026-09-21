# The registry the mirror workflows (T131) target.
output "container_registry_name" {
  description = "Name of the DR registry."
  value       = module.container_registry.container_registry_name
}

output "container_registry_endpoint" {
  description = "Login server of the DR registry."
  value       = module.container_registry.container_registry_endpoint
}
