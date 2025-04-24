output "frontend_url" {
  description = "URL to access the frontend application"
  value       = module.frontend.fqdn
}

output "zipkin_url" {
  description = "URL to access Zipkin monitoring"
  value       = module.zipkin.fqdn
}