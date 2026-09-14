# Outputs consumed by fdev/security and fdev/workload, and by the operators.
output "vpc_id" {
  description = "ID of the fdev spoke VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the fdev spoke."
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by subnet key."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private transit subnet IDs keyed by subnet key."
  value       = module.network.private_subnet_ids
}

output "private_route_table_ids" {
  description = "Private route table IDs keyed by subnet key."
  value       = module.network.private_route_table_ids
}

output "nat_gateway_ids" {
  description = "Empty by design: a full-profile spoke consumes the shared hub and creates no NAT gateway."
  value       = module.network.nat_gateway_ids
}

output "transit_gateway_id" {
  description = "ID of the shared transit gateway discovered by standard name, or null while transit is off."
  value       = var.transit_enabled ? data.aws_ec2_transit_gateway.shared[0].id : null
}

output "transit_attachment_id" {
  description = "ID of this spoke's transit gateway attachment."
  value       = module.network.transit_attachment_id
}

output "flow_log_group_arn" {
  description = "ARN of the encrypted VPC flow-log group."
  value       = module.network.flow_log_group_arn
}
