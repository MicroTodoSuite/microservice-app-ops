# Names, subnet topology, discovery keys, and transversal tags are built only
# in this root (PC-IAC-012 and PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  shared_prefix     = "${var.client}-${var.project}-shd"

  vpc_name     = "${local.governance_prefix}-vpc-main"
  cluster_name = "${local.governance_prefix}-eks-main"

  # EKS rejects a small set of zone IDs for cluster subnets. The account-specific
  # IDs are read from aws_availability_zone rather than guessed from zone names.
  eks_disallowed_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]

  zones = {
    for index, zone in var.availability_zones : regex("[a-z]$", zone) => {
      name         = data.aws_availability_zone.selected[zone].name
      public_cidr  = var.public_subnet_cidrs[index]
      private_cidr = var.private_subnet_cidrs[index]
    }
  }

  cluster_subnet_tag = { "kubernetes.io/cluster/${local.cluster_name}" = "shared" }
  public_subnet_tags = merge(local.cluster_subnet_tag, { "kubernetes.io/role/elb" = "1" })
  private_subnet_tags = merge(
    local.cluster_subnet_tag,
    {
      "kubernetes.io/role/internal-elb" = "1"
      "karpenter.sh/discovery"          = local.cluster_name
    },
  )

  subnets = merge(
    {
      for letter, zone in local.zones : "pub${letter}" => {
        name              = "${local.governance_prefix}-sub-pub${letter}"
        availability_zone = zone.name
        cidr_block        = zone.public_cidr
        tier              = "public"
        route_table_name  = null
        egress            = "none"
        nat_gateway_key   = null
        tags              = local.public_subnet_tags
      }
    },
    {
      for letter, zone in local.zones : "priv${letter}" => {
        name              = "${local.governance_prefix}-sub-priv${letter}"
        availability_zone = zone.name
        cidr_block        = zone.private_cidr
        tier              = "private"
        route_table_name  = "${local.governance_prefix}-rtb-priv${letter}"
        egress            = "transit"
        nat_gateway_key   = null
        tags              = local.private_subnet_tags
      }
    },
  )

  private_subnet_keys = [for letter in sort(keys(local.zones)) : "priv${letter}"]
  nat_gateways        = {}

  shared_tgw_name             = "${local.shared_prefix}-tgw-egress"
  shared_hub_attachment_name  = "${local.shared_prefix}-tgwa-egress"
  shared_hub_route_table_name = "${local.shared_prefix}-rtb-tgwhub"
  spoke_route_table_name      = "${local.governance_prefix}-rtb-tgw"

  transit_attachment = {
    name               = "${local.governance_prefix}-tgwa-spoke"
    subnet_keys        = local.private_subnet_keys
    route_table_id     = data.aws_ec2_transit_gateway_route_table.spoke.id
    hub_attachment_id  = data.aws_ec2_transit_gateway_vpc_attachment.hub.id
    hub_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id
  }

  flow_log = {
    name                     = "${local.governance_prefix}-fl-main"
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
