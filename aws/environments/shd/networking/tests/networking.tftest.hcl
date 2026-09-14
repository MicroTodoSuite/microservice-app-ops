# Plan-time contract of the shd/networking centralized egress hub.
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
  environment          = "shd"
  aws_account_id       = "123456789012"
  aws_region           = "us-east-1"
  deploy_role_arn      = "arn:aws:iam::123456789012:role/terraform-deploy"
  vpc_cidr             = "10.50.0.0/16"
  availability_zones   = ["us-east-1a"]
  public_subnet_cidrs  = ["10.50.0.0/24"]
  private_subnet_cidrs = ["10.50.16.0/20"]
  spoke_vpc_cidrs = {
    fdev = "10.40.0.0/16"
    fstg = "10.20.0.0/16"
    fprd = "10.30.0.0/16"
  }
}

run "builds_one_nat_and_one_elastic_ip_for_the_egress_hub" {
  command = plan

  assert {
    condition     = toset(keys(local.subnets)) == toset(["puba", "priva"]) && toset(keys(local.nat_gateways)) == toset(["egress"])
    error_message = "The shared egress VPC needs exactly one public subnet, one private subnet, and one NAT gateway."
  }

  assert {
    condition     = local.nat_gateways.egress.name == "lex-mts-shd-nat-egress" && local.nat_gateways.egress.eip_name == "lex-mts-shd-eip-egress"
    error_message = "The hub must expose exactly one standard-named NAT gateway and Elastic IP."
  }
}

run "declares_exactly_the_three_full_profile_spokes" {
  command = plan

  assert {
    condition     = toset(keys(local.spokes)) == toset(["fdev", "fstg", "fprd"])
    error_message = "Only the three full-profile environments may use the shared hub."
  }

  assert {
    condition     = local.spokes.fdev.vpc_cidr == "10.40.0.0/16" && local.spokes.fstg.vpc_cidr == "10.20.0.0/16" && local.spokes.fprd.vpc_cidr == "10.30.0.0/16"
    error_message = "The spokes must retain the reviewed legacy CIDR allocation."
  }

  assert {
    condition     = local.spokes.fdev.route_table_name == "lex-mts-fdev-rtb-tgw" && local.spokes.fstg.route_table_name == "lex-mts-fstg-rtb-tgw" && local.spokes.fprd.route_table_name == "lex-mts-fprd-rtb-tgw"
    error_message = "Each spoke needs its own standard-named transit gateway route table."
  }
}

run "reads_the_shared_flow_log_key_and_role_by_name" {
  command = plan

  assert {
    condition     = data.aws_kms_alias.flow_log.name == "alias/lex-mts-shd-kms-flowlogs" && data.aws_iam_role.flow_log.name == "lex-mts-shd-role-flowlogs"
    error_message = "The hub must read shd/security's flow-log key and role by standard name."
  }

  assert {
    condition     = local.flow_log.log_group_name == "/aws/vpc-flow-logs/lex-mts-shd-vpc-egress"
    error_message = "The hub flow-log group must use the standard egress VPC name."
  }
}

run "rejects_an_environment_other_than_shd" {
  command = plan

  variables {
    environment = "fdev"
  }

  expect_failures = [var.environment]
}

run "rejects_more_than_one_hub_zone" {
  command = plan

  variables {
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.50.0.0/24", "10.50.1.0/24"]
    private_subnet_cidrs = ["10.50.16.0/20", "10.50.32.0/20"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_an_incomplete_spoke_set" {
  command = plan

  variables {
    spoke_vpc_cidrs = {
      fdev = "10.40.0.0/16"
      fstg = "10.20.0.0/16"
    }
  }

  expect_failures = [var.spoke_vpc_cidrs]
}

run "rejects_subnet_lists_that_do_not_match_the_zone" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.50.0.0/24", "10.50.1.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs]
}

run "rejects_a_zone_that_is_not_an_availability_zone" {
  command = plan

  override_data {
    target = data.aws_availability_zone.selected["us-east-1a"]
    values = { zone_type = "local-zone", zone_id = "use1-lax1-az1" }
  }

  expect_failures = [data.aws_availability_zone.selected]
}
