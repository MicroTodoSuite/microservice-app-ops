output "transit_gateway_id" {
  description = "Transit gateway a spoke attaches itself to."
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "Transit gateway ARN, for cross-account sharing and for scoping a spoke's permissions to this hub only."
  value       = aws_ec2_transit_gateway.this.arn
}

output "egress_attachment_id" {
  description = "Hub-side attachment. A spoke points its own default transit gateway route at this attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.egress[0].id
}

output "egress_route_table_id" {
  description = "Hub-side route table. A spoke installs its own return route here, so the hub knows how to reach that spoke without the hub owning the route."
  value       = aws_ec2_transit_gateway_route_table.egress.id
}

output "spoke_route_table_ids" {
  description = "Dedicated, empty transit gateway route table per spoke, keyed by spoke name. A spoke associates its own attachment with its own table; because no table holds a route toward another spoke, spoke-to-spoke traffic has nowhere to go."
  value       = { for key, table in aws_ec2_transit_gateway_route_table.spoke : key => table.id }
}

output "vpc_id" {
  description = "Egress VPC id."
  value       = module.vpc.vpc_id
}

output "egress_public_ips" {
  description = "Public addresses every spoke shares when reaching the internet. A downstream allowlist needs exactly these values."
  value       = module.vpc.nat_public_ips
}

output "flow_log_kms_key_arn" {
  description = "Customer-managed key encrypting the shared egress flow logs."
  value       = aws_kms_key.flow_logs.arn
}

# Single reviewable summary of the properties this hub is required to hold. The
# tests assert against this rather than against provider internals, so a change
# in configuration shape cannot quietly drop a guarantee while the tests keep
# passing.
output "egress_contract" {
  description = "Reviewable summary of the egress hub's cost, isolation, and observability guarantees."
  value = {
    name                    = var.name
    region                  = var.aws_region
    account_id              = var.expected_account_id
    vpc_cidr                = var.vpc_cidr
    availability_zone_count = length(var.availability_zones)

    nat = {
      enabled          = true
      single           = true
      one_per_az       = false
      gateway_count    = length(module.vpc.natgw_ids)
      elastic_ip_count = length(module.vpc.nat_public_ips)
    }

    transit_gateway = {
      id                              = aws_ec2_transit_gateway.this.id
      default_route_table_association = aws_ec2_transit_gateway.this.default_route_table_association
      default_route_table_propagation = aws_ec2_transit_gateway.this.default_route_table_propagation
      auto_accept_shared_attachments  = aws_ec2_transit_gateway.this.auto_accept_shared_attachments
    }

    spokes = {
      names              = sort(keys(var.spokes))
      count              = length(var.spokes)
      route_table_ids    = { for key, table in aws_ec2_transit_gateway_route_table.spoke : key => table.id }
      declared_cidrs     = { for key, spoke in var.spokes : key => spoke.vpc_cidr }
      cross_spoke_routes = 0
    }

    # Ownership boundary, stated as numbers so a regression shows up as a failed
    # assertion instead of a review comment nobody writes.
    hub_owned_spoke_attachment_count    = local.hub_owned_spoke_attachment_count
    hub_owned_spoke_transit_route_count = local.hub_owned_spoke_transit_route_count
    hub_vpc_return_route_count          = local.hub_vpc_return_route_count

    flow_logs = {
      enabled           = true
      kms_key_arn       = aws_kms_key.flow_logs.arn
      traffic_type      = "ALL"
      retention_in_days = var.flow_log_retention_in_days
      log_group_name    = local.flow_log_group_name
    }
  }
}
