# Names, subnets, tags, and the flow log of the eco/networking root, built here and nowhere
# else (PC-IAC-012, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"
  shared_prefix     = "${var.client}-${var.project}-shd"

  # The cluster eco/workload creates; the subnets carry its discovery tags from the start.
  cluster_name = "${local.governance_prefix}-eks-main"
  vpc_name     = "${local.governance_prefix}-vpc-main"

  # Zone IDs where EKS does not place cluster subnets (EKS user guide, subnet requirements).
  eks_disallowed_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]

  # One entry per zone, keyed by its letter: a, b, c. The name comes through the zone check,
  # so no subnet is planned in a zone that failed it.
  zones = {
    for index, zone in var.availability_zones : regex("[a-z]$", zone) => {
      name         = data.aws_availability_zone.selected[zone].name
      public_cidr  = var.public_subnet_cidrs[index]
      private_cidr = var.private_subnet_cidrs[index]
    }
  }

  # The tags the AWS Load Balancer Controller and Karpenter discover subnets by.
  cluster_subnet_tag  = { "kubernetes.io/cluster/${local.cluster_name}" = "shared" }
  public_subnet_tags  = merge(local.cluster_subnet_tag, { "kubernetes.io/role/elb" = "1" })
  private_subnet_tags = merge(local.cluster_subnet_tag, { "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = local.cluster_name })

  # Each private subnet leaves through the NAT gateway of its own zone, the topology the
  # legacy dev root ran.
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
        egress            = "nat"
        nat_gateway_key   = letter
        tags              = local.private_subnet_tags
      }
    },
  )

  nat_gateways = {
    for letter, zone in local.zones : letter => {
      name       = "${local.governance_prefix}-nat-${letter}"
      eip_name   = "${local.governance_prefix}-eip-${letter}"
      subnet_key = "pub${letter}"
    }
  }

  flow_log = {
    name                    = "${local.governance_prefix}-fl-main"
    log_group_name          = "/aws/vpc-flow-logs/${local.vpc_name}"
    log_group_standard_name = "${local.governance_prefix}-cwl-flowlogs"
    retention_in_days       = var.flow_log_retention_in_days
    kms_key_arn             = data.aws_kms_alias.flow_log.target_key_arn
    iam_role_arn            = data.aws_iam_role.flow_log.arn
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
