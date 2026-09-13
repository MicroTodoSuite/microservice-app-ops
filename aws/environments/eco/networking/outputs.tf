# Outputs of the eco/networking root, read by eco/security and eco/workload.
output "vpc_id" {
  description = "ID of the economical environment's VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by subnet key, such as puba."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by subnet key, such as priva; the cluster and its nodes use these."
  value       = module.network.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by zone letter."
  value       = module.network.nat_gateway_ids
}

output "flow_log_group_arn" {
  description = "ARN of the encrypted VPC flow-log group."
  value       = module.network.flow_log_group_arn
}
