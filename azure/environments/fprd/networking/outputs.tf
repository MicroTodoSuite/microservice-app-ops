# Identifiers the security and workload roots look up by name, and the ingress
# binding GitOps (T129) and DNS (T134) consume.
output "virtual_network_name" {
  description = "Name of the DR VNet."
  value       = module.network.virtual_network_name
}

output "node_subnet_id" {
  description = "Resource ID of the private node subnet."
  value       = module.network.subnet_ids["nodes"]
}

output "ingress_public_ip_name" {
  description = "Name of the static ingress address, for the azure-pip-name Service annotation."
  value       = module.ingress_public_ip.public_ip_name
}

output "ingress_public_ip_resource_group_name" {
  description = "Resource group of the static ingress address, for the azure-load-balancer-resource-group Service annotation."
  value       = module.ingress_public_ip.public_ip_resource_group_name
}

output "ingress_public_ip_endpoint" {
  description = "IPv4 address of the static ingress address."
  value       = module.ingress_public_ip.public_ip_endpoint
}

output "ingress_public_ip_dns_name" {
  description = "Provider FQDN of the ingress address, the CNAME target of full-prod-azure.microtodosuite.online (T134)."
  value       = module.ingress_public_ip.public_ip_dns_name
}

output "traffic_routing_data" {
  description = "How eligible traffic reaches Azure: health-checked failover only, never active-active until a replicated data store exists (constitution principle 12)."
  value = {
    mode                  = "failover"
    active_active_enabled = var.enable_active_active
  }
}
