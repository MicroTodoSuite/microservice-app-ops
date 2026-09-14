# Outputs consumed by the three full-profile networking roots and by operators.
output "vpc_id" {
  description = "ID of the shared egress VPC."
  value       = module.egress_network.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the shared egress VPC."
  value       = module.egress_network.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs of the shared egress VPC."
  value       = module.egress_network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private attachment subnet IDs of the shared egress VPC."
  value       = module.egress_network.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "The single NAT gateway ID, keyed by egress."
  value       = module.egress_network.nat_gateway_ids
}

output "nat_eip_allocation_ids" {
  description = "The single NAT Elastic IP allocation ID, keyed by egress."
  value       = module.egress_network.nat_eip_allocation_ids
}

output "flow_log_group_arn" {
  description = "ARN of the encrypted VPC flow-log group."
  value       = module.egress_network.flow_log_group_arn
}

output "transit_gateway_id" {
  description = "ID of the transit gateway every full-profile spoke attaches to."
  value       = module.transit_egress.transit_gateway_id
}

output "transit_gateway_arn" {
  description = "ARN of the shared transit gateway."
  value       = module.transit_egress.transit_gateway_arn
}

output "hub_attachment_id" {
  description = "ID of the egress VPC's transit gateway attachment."
  value       = module.transit_egress.hub_attachment_id
}

output "hub_route_table_id" {
  description = "ID of the hub-side transit gateway route table."
  value       = module.transit_egress.hub_route_table_id
}

output "spoke_route_table_ids" {
  description = "Dedicated transit gateway route table ID for each full-profile spoke."
  value       = module.transit_egress.spoke_route_table_ids
}
