# Plan-time tests of the eco/networking root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias = "principal"

  mock_data "aws_availability_zone" {
    defaults = { zone_type = "availability-zone", zone_id = "use1-az1" }
  }

  mock_data "aws_kms_alias" {
    defaults = { target_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/lex-mts-shd-role-flowlogs" }
  }
}

variables {
  client               = "lex"
  project              = "mts"
  environment          = "eco"
  aws_account_id       = "123456789012"
  aws_region           = "us-east-1"
  deploy_role_arn      = "arn:aws:iam::123456789012:role/terraform-deploy"
  vpc_cidr             = "10.10.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
}

run "builds_a_public_and_a_private_subnet_and_a_nat_gateway_per_zone" {
  command = plan

  assert {
    condition     = toset(keys(local.subnets)) == toset(["priva", "privb", "privc", "puba", "pubb", "pubc"]) && toset(keys(local.nat_gateways)) == toset(["a", "b", "c"])
    error_message = "Every zone needs one public subnet, one private subnet, and one NAT gateway."
  }

  assert {
    condition     = local.subnets["privb"].name == "lex-mts-eco-sub-privb" && local.subnets["privb"].availability_zone == "us-east-1b" && local.subnets["privb"].cidr_block == "10.10.32.0/20" && local.subnets["privb"].nat_gateway_key == "b" && local.nat_gateways["b"].subnet_key == "pubb"
    error_message = "A private subnet must leave through the NAT gateway in the public subnet of its own zone."
  }

  assert {
    condition     = local.vpc_name == "lex-mts-eco-vpc-main" && local.nat_gateways["a"].name == "lex-mts-eco-nat-a" && local.nat_gateways["a"].eip_name == "lex-mts-eco-eip-a"
    error_message = "The root must build the eco standard names (MTS-IAC-101)."
  }
}

run "tags_the_subnets_for_load_balancer_and_karpenter_discovery" {
  command = plan

  assert {
    condition     = local.subnets["puba"].tags == { "kubernetes.io/cluster/lex-mts-eco-eks-main" = "shared", "kubernetes.io/role/elb" = "1" }
    error_message = "Public subnets need the cluster tag and the internet-facing load balancer role."
  }

  assert {
    condition     = local.subnets["priva"].tags == { "kubernetes.io/cluster/lex-mts-eco-eks-main" = "shared", "kubernetes.io/role/internal-elb" = "1", "karpenter.sh/discovery" = "lex-mts-eco-eks-main" }
    error_message = "Private subnets need the cluster tag, the internal load balancer role, and Karpenter's discovery tag."
  }
}

run "reads_the_shared_flow_log_key_and_role_by_name" {
  command = plan

  assert {
    condition     = data.aws_kms_alias.flow_log.name == "alias/lex-mts-shd-kms-flowlogs" && data.aws_iam_role.flow_log.name == "lex-mts-shd-role-flowlogs"
    error_message = "The flow log must use shd/security's key and role, found by their standard names."
  }

  assert {
    condition     = local.flow_log.log_group_name == "/aws/vpc-flow-logs/lex-mts-eco-vpc-main" && local.flow_log.retention_in_days == 90
    error_message = "The flow-log group must sit under /aws/vpc-flow-logs/, the prefix shd/security's key accepts."
  }
}

run "removes_only_the_nat_egress_when_nat_gateways_are_disabled" {
  command = plan

  variables {
    nat_gateways_enabled = false
  }

  assert {
    condition     = length(local.nat_gateways) == 0 && alltrue([for key in ["priva", "privb", "privc"] : local.subnets[key].egress == "none" && local.subnets[key].nat_gateway_key == null])
    error_message = "Without NAT gateways, no gateway or Elastic IP is planned and no private subnet routes through one."
  }

  assert {
    condition     = toset(keys(local.subnets)) == toset(["priva", "privb", "privc", "puba", "pubb", "pubc"]) && local.subnets["privb"].route_table_name == "lex-mts-eco-rtb-privb" && local.subnets["privb"].cidr_block == "10.10.32.0/20"
    error_message = "The lifecycle's down transition keeps every subnet and route table, so the VPC and eco/security's security groups survive it."
  }
}

run "rejects_an_environment_other_than_eco" {
  command = plan

  variables {
    environment = "fdev"
  }

  expect_failures = [var.environment]
}

run "rejects_a_single_zone" {
  command = plan

  variables {
    availability_zones   = ["us-east-1a"]
    public_subnet_cidrs  = ["10.10.0.0/24"]
    private_subnet_cidrs = ["10.10.16.0/20"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_subnet_lists_that_do_not_match_the_zones" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.10.0.0/24", "10.10.1.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs]
}

run "rejects_a_zone_eks_does_not_allow" {
  command = plan

  override_data {
    target = data.aws_availability_zone.selected["us-east-1b"]
    values = { zone_type = "availability-zone", zone_id = "use1-az3" }
  }

  expect_failures = [data.aws_availability_zone.selected]
}
