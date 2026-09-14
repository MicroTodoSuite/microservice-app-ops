# The shared egress VPC: one public subnet, one private attachment subnet, and
# exactly one NAT gateway and Elastic IP.
module "egress_network" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//network?ref=network-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                  = var.client
  project                 = var.project
  environment             = var.environment
  vpc                     = { name = local.vpc_name, cidr_block = var.vpc_cidr }
  internet_gateway_name   = "${local.governance_prefix}-igw-egress"
  public_route_table_name = "${local.governance_prefix}-rtb-public"
  subnets                 = local.subnets
  nat_gateways            = local.nat_gateways
  transit_gateway_id      = ""
  transit_attachment      = null
  flow_log                = local.flow_log
}

# The isolated transit hub. It creates one empty route table per full-profile
# spoke; each spoke's own networking state later owns its attachment and routes.
module "transit_egress" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//transit-egress?ref=transit-egress-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client               = var.client
  project              = var.project
  environment          = var.environment
  transit_gateway_name = "${local.governance_prefix}-tgw-egress"
  hub_attachment_name  = "${local.governance_prefix}-tgwa-egress"
  hub_route_table_name = "${local.governance_prefix}-rtb-tgwhub"

  hub_vpc = {
    id                    = module.egress_network.vpc_id
    cidr_block            = module.egress_network.vpc_cidr
    attachment_subnet_ids = values(module.egress_network.private_subnet_ids)
    public_route_table_id = module.egress_network.public_route_table_id
  }

  spokes = local.spokes
}
