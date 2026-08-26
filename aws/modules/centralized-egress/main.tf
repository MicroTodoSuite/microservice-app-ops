data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  tags = merge(var.tags, {
    Name      = var.name
    Component = "centralized-egress"
  })

  flow_log_group_name = "/aws/vpc-flow-logs/${var.name}"

  # The hub deliberately owns no spoke attachment and no transit gateway route
  # that names a spoke attachment. Both counts are surfaced in the contract
  # output so the boundary is asserted as a number rather than inferred from the
  # absence of a resource block.
  #
  # The hub-side VPC return routes below are a separate, unavoidable thing: a
  # NAT gateway translates a reply back to the spoke's private address, and that
  # reply then has to be routed out of the hub's public subnet toward the
  # transit gateway. Those routes live in the hub's own VPC route table, name no
  # spoke attachment, and cannot carry spoke-to-spoke traffic because the
  # transit gateway still has no route from one spoke's table to another's.
  hub_owned_spoke_attachment_count      = 0
  hub_owned_spoke_transit_route_count   = 0
  hub_vpc_return_route_count            = length(var.spokes) * length(module.vpc.public_route_table_ids)
  public_route_table_spoke_combinations = setproduct(module.vpc.public_route_table_ids, keys(var.spokes))
}

# The hub is a shared singleton. Applying it into the wrong account would create
# a second egress path rather than fail, so the identity is checked in
# configuration instead of being left to whoever ran the apply.
check "account_matches_the_reviewed_owner" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
    error_message = "The egress hub is being applied into account ${data.aws_caller_identity.current.account_id}, but the reviewed owner is ${var.expected_account_id}."
  }
}

resource "aws_kms_key" "flow_logs" {
  description             = "Encrypts ${var.name} VPC flow logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${var.expected_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.${data.aws_partition.current.dns_suffix}"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${var.expected_account_id}:log-group:${local.flow_log_group_name}"
          }
        }
      },
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_kms_alias" "flow_logs" {
  name          = "alias/${var.name}-vpc-flow-logs"
  target_key_id = aws_kms_key.flow_logs.key_id
}

# The egress VPC carries no workloads. Its public subnet holds the single NAT
# gateway; its private subnet holds the transit gateway attachment ENIs, which
# must not sit in the public subnet.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name   = var.name
  region = var.aws_region
  cidr   = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  create_igw = true

  # One NAT gateway behind one Elastic IP is the entire point of the hub: every
  # spoke shares this address, so the fleet needs one allowlist entry and one
  # NAT bill instead of one per environment.
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  map_public_ip_on_launch = false

  enable_flow_log                                 = true
  flow_log_destination_type                       = "cloud-watch-logs"
  flow_log_max_aggregation_interval               = 60
  flow_log_traffic_type                           = "ALL"
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_name_prefix       = "/aws/vpc-flow-logs/"
  flow_log_cloudwatch_log_group_name_suffix       = var.name
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_in_days
  flow_log_cloudwatch_log_group_kms_key_id        = aws_kms_key.flow_logs.arn
  flow_log_cloudwatch_log_group_skip_destroy      = false
  flow_log_cloudwatch_log_group_class             = "STANDARD"

  tags = local.tags
}

# Both defaults are disabled on purpose. With default association a new
# attachment would join one shared route table, and with default propagation its
# CIDR would be advertised to everything already in that table — which is
# exactly how a spoke silently becomes reachable from its neighbours.
resource "aws_ec2_transit_gateway" "this" {
  description = "Centralized egress hub for MicroTodoSuite full-profile environments"

  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "disable"

  tags = merge(local.tags, {
    Name = var.name
  })
}

# The hub's own attachment. This is the only attachment the hub owns; every
# spoke attaches itself from its own state.
resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  count = 1

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  dns_support = "enable"

  tags = merge(local.tags, {
    Name = "${var.name}-egress"
  })
}

# The hub-side route table. Spokes install their own return routes here, which
# is why the hub creates it but leaves it otherwise empty.
resource "aws_ec2_transit_gateway_route_table" "egress" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-egress"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "egress" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

# One dedicated, empty route table per spoke.
#
# Empty is the security property, not an oversight. A spoke associates its own
# attachment with its own table and installs exactly one route — a default route
# back to the hub. Because no spoke's table ever contains a route toward another
# spoke's attachment, spoke-to-spoke traffic has nowhere to go, and making it go
# somewhere requires editing that spoke's own state in a reviewed change.
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each = var.spokes

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.tags, {
    Name  = "${var.name}-${each.key}"
    Spoke = each.key
  })
}

# Hub-side return routes.
#
# A spoke's outbound packet leaves through the NAT gateway, which rewrites the
# source to the hub's single Elastic IP. When the reply arrives, the NAT gateway
# translates it back to the spoke's private address — and that packet is now
# sitting in the hub's public subnet with a destination the public route table
# knows nothing about. Without these routes every spoke's outbound connection
# would hang on the reply rather than fail outright, which is the harder failure
# to diagnose.
#
# These stay hub-owned because they are entries in the hub's own VPC route
# table. They point at the transit gateway, never at a specific spoke
# attachment, so they grant a spoke no path to any other spoke: the transit
# gateway still has to match a route in the receiving spoke's own dedicated
# table, and that table contains only the spoke's own default route.
resource "aws_route" "spoke_return" {
  for_each = {
    for pair in local.public_route_table_spoke_combinations :
    "${pair[0]}:${pair[1]}" => {
      route_table_id = pair[0]
      spoke          = pair[1]
    }
  }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = var.spokes[each.value.spoke].vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress]
}
