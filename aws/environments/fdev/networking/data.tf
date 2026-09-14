# Shared resources are discovered by their standard Name tags. This keeps the
# spoke state from owning or deleting the hub's transit resources. The transit
# lookups exist only while transit_enabled, so the spoke plans without the hub,
# which the lifecycle's full down transition destroys.
data "aws_availability_zone" "selected" {
  for_each = toset(var.availability_zones)
  provider = aws.principal

  name = each.value

  lifecycle {
    postcondition {
      condition     = self.zone_type == "availability-zone" && !contains(local.eks_disallowed_zone_ids, self.zone_id)
      error_message = "Every zone must be an Availability Zone whose zone ID EKS accepts for cluster subnets."
    }
  }
}

data "aws_kms_alias" "flow_log" {
  provider = aws.principal

  name = "alias/${local.shared_prefix}-kms-flowlogs"
}

data "aws_iam_role" "flow_log" {
  provider = aws.principal

  name = "${local.shared_prefix}-role-flowlogs"
}

data "aws_ec2_transit_gateway" "shared" {
  count    = var.transit_enabled ? 1 : 0
  provider = aws.principal

  filter {
    name   = "tag:Name"
    values = [local.shared_tgw_name]
  }
}

data "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  count    = var.transit_enabled ? 1 : 0
  provider = aws.principal

  filter {
    name   = "tag:Name"
    values = [local.shared_hub_attachment_name]
  }
}

data "aws_ec2_transit_gateway_route_table" "hub" {
  count    = var.transit_enabled ? 1 : 0
  provider = aws.principal

  filter {
    name   = "tag:Name"
    values = [local.shared_hub_route_table_name]
  }
}

data "aws_ec2_transit_gateway_route_table" "spoke" {
  count    = var.transit_enabled ? 1 : 0
  provider = aws.principal

  filter {
    name   = "tag:Name"
    values = [local.spoke_route_table_name]
  }
}
