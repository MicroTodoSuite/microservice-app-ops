# Names, topology, and tags of the shd/networking root, built here and nowhere
# else (PC-IAC-012, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  vpc_name          = "${local.governance_prefix}-vpc-egress"

  zone = {
    for index, zone in var.availability_zones : regex("[a-z]$", zone) => {
      name         = data.aws_availability_zone.selected[zone].name
      public_cidr  = var.public_subnet_cidrs[index]
      private_cidr = var.private_subnet_cidrs[index]
    }
  }
  hub_zone = one(values(local.zone))

  subnets = {
    puba = {
      name              = "${local.governance_prefix}-sub-puba"
      availability_zone = local.hub_zone.name
      cidr_block        = local.hub_zone.public_cidr
      tier              = "public"
      route_table_name  = null
      egress            = "none"
      nat_gateway_key   = null
      tags              = {}
    }
    priva = {
      name              = "${local.governance_prefix}-sub-priva"
      availability_zone = local.hub_zone.name
      cidr_block        = local.hub_zone.private_cidr
      tier              = "private"
      route_table_name  = "${local.governance_prefix}-rtb-priva"
      egress            = "nat"
      nat_gateway_key   = "egress"
      tags              = {}
    }
  }

  nat_gateways = {
    egress = {
      name       = "${local.governance_prefix}-nat-egress"
      eip_name   = "${local.governance_prefix}-eip-egress"
      subnet_key = "puba"
    }
  }

  spokes = {
    for environment, cidr in var.spoke_vpc_cidrs : environment => {
      vpc_cidr         = cidr
      route_table_name = "${var.client}-${var.project}-${environment}-rtb-tgw"
    }
  }

  flow_log = {
    name                     = "${local.governance_prefix}-fl-egress"
    log_group_name           = "/aws/vpc-flow-logs/${local.vpc_name}"
    log_group_standard_name  = "${local.governance_prefix}-cwl-flowlogs"
    retention_in_days        = var.flow_log_retention_in_days
    kms_key_arn              = data.aws_kms_alias.flow_log.target_key_arn
    iam_role_arn             = data.aws_iam_role.flow_log.arn
    traffic_type             = "ALL"
    max_aggregation_interval = 60
  }

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repository  = var.repository
  }
}
