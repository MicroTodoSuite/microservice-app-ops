# Plan-time contract of the fstg/networking transit spoke.
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

  mock_data "aws_ec2_transit_gateway" {
    defaults = { id = "tgw-12345678" }
  }

  mock_data "aws_ec2_transit_gateway_vpc_attachment" {
    defaults = { id = "tgw-attach-12345678" }
  }

  mock_data "aws_ec2_transit_gateway_route_table" {
    defaults = { id = "tgw-rtb-12345678" }
  }
}

variables {
  client               = "lex"
  project              = "mts"
  environment          = "fstg"
  aws_account_id       = "123456789012"
  aws_region           = "us-east-1"
  deploy_role_arn      = "arn:aws:iam::123456789012:role/terraform-deploy"
  vpc_cidr             = "10.20.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
}

run "builds_a_three_zone_transit_spoke_without_nat" {
  command = plan

  assert {
    condition     = toset(keys(local.subnets)) == toset(["puba", "pubb", "pubc", "priva", "privb", "privc"]) && length(local.nat_gateways) == 0
    error_message = "The full-staging spoke needs three public and three private subnets and no NAT gateway of its own."
  }

  assert {
    condition = alltrue([
      for key in ["priva", "privb", "privc"] : local.subnets[key].egress == "transit" && local.subnets[key].route_table_name == "lex-mts-fstg-rtb-priv${substr(key, 4, 1)}"
    ])
    error_message = "Every private fstg subnet must route through its own standard-named transit table."
  }

  assert {
    condition     = local.transit_attachment.name == "lex-mts-fstg-tgwa-spoke" && toset(local.transit_attachment.subnet_keys) == toset(["priva", "privb", "privc"])
    error_message = "The fstg attachment must use all three private subnets and a standard spoke name."
  }
}

run "reads_the_shared_hub_and_spoke_tables_by_standard_name" {
  command = plan

  assert {
    condition     = toset(one([for filter in data.aws_ec2_transit_gateway.shared.filter : filter if filter.name == "tag:Name"]).values) == toset(["lex-mts-shd-tgw-egress"])
    error_message = "The spoke must discover the shared transit gateway by its standard Name tag."
  }

  assert {
    condition     = toset(one([for filter in data.aws_ec2_transit_gateway_vpc_attachment.hub.filter : filter if filter.name == "tag:Name"]).values) == toset(["lex-mts-shd-tgwa-egress"])
    error_message = "The spoke must discover the hub attachment by its standard Name tag."
  }

  assert {
    condition     = toset(one([for filter in data.aws_ec2_transit_gateway_route_table.spoke.filter : filter if filter.name == "tag:Name"]).values) == toset(["lex-mts-fstg-rtb-tgw"])
    error_message = "The spoke must discover its dedicated transit table by its standard Name tag."
  }
}

run "reads_the_shared_flow_log_key_and_role_by_name" {
  command = plan

  assert {
    condition     = data.aws_kms_alias.flow_log.name == "alias/lex-mts-shd-kms-flowlogs" && data.aws_iam_role.flow_log.name == "lex-mts-shd-role-flowlogs"
    error_message = "The spoke must read shd/security's flow-log key and role by standard name."
  }
}

run "rejects_an_environment_other_than_fstg" {
  command = plan

  variables {
    environment = "fdev"
  }

  expect_failures = [var.environment]
}

run "rejects_a_zone_count_other_than_three" {
  command = plan

  variables {
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
    private_subnet_cidrs = ["10.20.16.0/20", "10.20.32.0/20"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_subnet_lists_that_do_not_match_the_zones" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
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
