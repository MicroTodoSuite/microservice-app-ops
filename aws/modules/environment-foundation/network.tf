resource "aws_kms_key" "vpc_flow_logs" {
  description             = "Encrypts ${local.cluster_name} VPC flow logs"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/vpc-flow-logs/${local.cluster_name}"
          }
        }
      },
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.cluster_name}-vpc-flow-logs"
  })
}

resource "aws_kms_alias" "vpc_flow_logs" {
  name          = "alias/${local.cluster_name}-vpc-flow-logs"
  target_key_id = aws_kms_key.vpc_flow_logs.key_id
}

locals {
  transit_egress = var.outbound_mode == "transit-egress"

  # A transit-egress spoke has no NAT gateway and therefore no Elastic IP: its
  # private default route leaves through the centrally owned transit gateway.
  nat_gateway_enabled = !local.transit_egress

  # Exact subnet tags the AWS Load Balancer Controller uses for discovery. They
  # are declared once here so the controller's contract and the subnets that
  # satisfy it can never drift apart.
  public_load_balancer_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_load_balancer_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  private_subnet_tags = merge(local.private_load_balancer_subnet_tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name   = local.cluster_name
  region = var.aws_region
  cidr   = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  # The internet gateway stays in every mode. In transit-egress it serves only
  # public load balancers in the public subnets; private workloads never reach
  # it because their default route points at the transit gateway.
  create_igw              = true
  enable_nat_gateway      = local.nat_gateway_enabled
  single_nat_gateway      = local.nat_gateway_enabled && var.single_nat_gateway
  one_nat_gateway_per_az  = local.nat_gateway_enabled && !var.single_nat_gateway
  map_public_ip_on_launch = false

  public_subnet_tags  = local.public_load_balancer_subnet_tags
  private_subnet_tags = local.private_subnet_tags

  enable_flow_log                                 = true
  flow_log_destination_type                       = "cloud-watch-logs"
  flow_log_max_aggregation_interval               = 60
  flow_log_traffic_type                           = "ALL"
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_name_prefix       = "/aws/vpc-flow-logs/"
  flow_log_cloudwatch_log_group_name_suffix       = local.cluster_name
  flow_log_cloudwatch_log_group_retention_in_days = 90
  flow_log_cloudwatch_log_group_kms_key_id        = aws_kms_key.vpc_flow_logs.arn
  flow_log_cloudwatch_log_group_skip_destroy      = false
  flow_log_cloudwatch_log_group_class             = "STANDARD"

  tags = local.tags
}

# In transit-egress the VPC module creates no default route for the private
# subnets, so this module supplies one per private route table. The route is the
# spoke's only path off-VPC for private workloads.
resource "aws_route" "private_transit_egress" {
  # The transit_gateway_id guard below reports a missing gateway as a reviewable
  # precondition failure; planning zero routes here keeps that message the only
  # error the operator has to read.
  count = local.transit_egress && var.transit_gateway_id != null ? length(var.private_subnet_cidrs) : 0

  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id
}

# A single-NAT environment must not launch private worker nodes until both the
# NAT gateway and its default route are ready. Referencing only these outputs
# avoids coupling node replacement to unrelated VPC resource destruction.
#
# This gate is deliberately left byte-identical to its pre-full-profile shape:
# the applied dev and demo foundations already track it, and widening its input
# would replace it for no behavioral gain. transit-egress gets its own gate.
resource "terraform_data" "private_egress_ready" {
  count = var.single_nat_gateway ? 1 : 0

  input = {
    nat_gateway_ids               = module.vpc.natgw_ids
    private_nat_gateway_route_ids = module.vpc.private_nat_gateway_route_ids
  }
}

# The transit-egress equivalent: private workers must not launch before their
# transit-gateway default routes exist, or they come up with no path off-VPC.
resource "terraform_data" "transit_egress_ready" {
  count = local.transit_egress ? 1 : 0

  input = {
    transit_gateway_id        = var.transit_gateway_id
    transit_gateway_route_ids = aws_route.private_transit_egress[*].id
  }
}
