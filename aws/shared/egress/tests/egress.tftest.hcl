# Root-level contract for the shared egress hub.
#
# The module tests prove the hub is built correctly. These prove this root is
# pointed at the right account, region, and spokes — the values that decide
# whether the correct hub gets built in the correct place.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "916491575487"
      arn        = "arn:aws:iam::916491575487:role/test"
      id         = "916491575487"
      user_id    = "test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

override_module {
  target = module.egress.module.vpc
  outputs = {
    vpc_id                       = "vpc-0egress0000000000"
    public_subnets               = ["subnet-egress-public-a"]
    private_subnets              = ["subnet-egress-private-a"]
    private_route_table_ids      = ["rtb-egress-private-a"]
    public_route_table_ids       = ["rtb-egress-public"]
    natgw_ids                    = ["nat-egress-a"]
    nat_ids                      = ["eipalloc-egress-a"]
    nat_public_ips               = ["203.0.113.10"]
    vpc_flow_log_id              = "fl-0egress0000000000"
    vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:916491575487:log-group:/aws/vpc-flow-logs/microtodosuite-egress"
  }
}

variables {
  expected_account_id = "916491575487"
}

run "defaults_target_the_reviewed_account_region_and_topology" {
  command = plan

  assert {
    condition     = output.egress_contract.account_id == "916491575487"
    error_message = "The hub must target the single reviewed AWS account."
  }

  assert {
    condition     = output.egress_contract.region == "us-east-1"
    error_message = "The hub must be in us-east-1, where every reviewed environment lives."
  }

  assert {
    condition     = output.egress_contract.nat.gateway_count == 1 && output.egress_contract.nat.elastic_ip_count == 1
    error_message = "The shared hub must resolve to exactly one NAT gateway and one Elastic IP."
  }

  assert {
    condition     = output.egress_contract.availability_zone_count == 1
    error_message = "The reviewed hub is single-AZ; widening it is a cost and availability decision."
  }
}

# The three full-profile spokes, and only those. An economical environment
# appearing here would make the platform that is supposed to be the rollback
# target depend on the thing being rolled out.
run "exactly_the_three_full_profile_spokes_are_declared" {
  command = plan

  assert {
    condition     = output.egress_contract.spokes.names == tolist(["full-dev", "full-prod", "full-staging"])
    error_message = "The hub must declare exactly the three full-profile spokes."
  }

  assert {
    condition = output.egress_contract.spokes.declared_cidrs == {
      "full-dev"     = "10.40.0.0/16"
      "full-staging" = "10.20.0.0/16"
      "full-prod"    = "10.30.0.0/16"
    }
    error_message = "Spoke CIDRs must match the reviewed allocation exactly."
  }

  assert {
    condition = alltrue([
      for name in output.egress_contract.spokes.names : !startswith(name, "economical")
    ])
    error_message = "No economical environment may attach to the shared hub; the economical platform is the rollback target and must keep its own independent egress."
  }
}

run "hub_never_owns_a_spoke_attachment_or_transit_route" {
  command = plan

  assert {
    condition     = output.egress_contract.hub_owned_spoke_attachment_count == 0
    error_message = "A spoke attachment belongs to the spoke's own state."
  }

  assert {
    condition     = output.egress_contract.hub_owned_spoke_transit_route_count == 0
    error_message = "Spoke transit gateway route tables must be created empty."
  }

  assert {
    condition     = output.egress_contract.spokes.cross_spoke_routes == 0
    error_message = "No route may exist from one spoke's route table toward another spoke."
  }
}

run "a_wrong_account_is_rejected_rather_than_duplicating_the_hub" {
  command = plan

  variables {
    expected_account_id = "123456789012"
  }

  expect_failures = [
    var.expected_account_id,
  ]
}

run "a_region_other_than_us_east_1_is_rejected" {
  command = plan

  variables {
    aws_region = "us-west-2"
  }

  expect_failures = [
    var.aws_region,
  ]
}
