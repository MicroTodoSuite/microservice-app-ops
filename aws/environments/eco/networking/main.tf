# The eco/networking root: the economical environment's VPC, first in the PC-IAC-022 order.
# Every private subnet has its own NAT gateway; the flow logs go to a group encrypted with
# shd/security's key and delivered by its role.
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
  transit_gateway_id      = ""
  transit_attachment      = null
  flow_log                = local.flow_log
}
