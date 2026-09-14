# The fstg VPC is a transit-egress spoke. Its private subnets route through the
# shared shd hub, and this state owns only the spoke attachment and its routes.
module "network" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//network?ref=network-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client                  = var.client
  project                 = var.project
  environment             = var.environment
  vpc                     = { name = local.vpc_name, cidr_block = var.vpc_cidr }
  internet_gateway_name   = "${local.governance_prefix}-igw-main"
  public_route_table_name = "${local.governance_prefix}-rtb-public"
  subnets                 = local.subnets
  nat_gateways            = local.nat_gateways
  transit_gateway_id      = data.aws_ec2_transit_gateway.shared.id
  transit_attachment      = local.transit_attachment
  flow_log                = local.flow_log
}
