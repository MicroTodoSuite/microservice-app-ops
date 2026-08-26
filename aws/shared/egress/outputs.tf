# These are the values a spoke root needs in order to attach itself. They are
# published as plain outputs so a spoke can read them from this root's state
# without the hub ever needing write access to a spoke, or the spoke to the hub.

output "transit_gateway_id" {
  description = "Transit gateway a spoke sets as transit_gateway_id in its own foundation."
  value       = module.egress.transit_gateway_id
}

output "transit_gateway_arn" {
  description = "Transit gateway ARN, for scoping a spoke's attachment permissions to this hub only."
  value       = module.egress.transit_gateway_arn
}

output "egress_attachment_id" {
  description = "Hub-side attachment a spoke points its own default transit gateway route at."
  value       = module.egress.egress_attachment_id
}

output "egress_route_table_id" {
  description = "Hub-side route table a spoke installs its own return route into."
  value       = module.egress.egress_route_table_id
}

output "spoke_route_table_ids" {
  description = "Dedicated, empty route table per spoke, keyed by spoke name."
  value       = module.egress.spoke_route_table_ids
}

output "vpc_id" {
  description = "Egress VPC id."
  value       = module.egress.vpc_id
}

output "egress_public_ips" {
  description = "The addresses every full-profile environment shares when reaching the internet. A third-party allowlist needs exactly these values and no others."
  value       = module.egress.egress_public_ips
}

output "egress_contract" {
  description = "Reviewable summary of the hub's cost, isolation, and observability guarantees. This is the object a stage gate compares against the approved plan."
  value       = module.egress.egress_contract
}
