# Contract for the centralized egress hub.
#
# The hub owns exactly one shared way off the network — one NAT gateway behind
# one Elastic IP — plus the transit gateway and one deliberately empty route
# table per spoke. It owns nothing that belongs to a spoke: no spoke VPC
# attachment, no spoke default route, no spoke return route. That split is what
# keeps one spoke from reaching another, so it is asserted here as absence, not
# merely described in a comment.

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

# The transit gateway id is computed, so every route table's transit_gateway_id
# is unknown at plan time and any comparison against it is unevaluable. Pinning
# the id here keeps these assertions in `plan`, where they can run on every
# change, instead of demoting them to an `apply` that needs real AWS.
override_resource {
  target          = aws_ec2_transit_gateway.this
  override_during = plan

  values = {
    id  = "tgw-0123456789abcdef0"
    arn = "arn:aws:ec2:us-east-1:916491575487:transit-gateway/tgw-0123456789abcdef0"
  }
}

# Same reason as the transit gateway: the key ARN is computed, so the assertion
# that flow logs use *this* key rather than an AWS-managed default cannot be
# evaluated at plan time unless the ARN is pinned.
override_resource {
  target          = aws_kms_key.flow_logs
  override_during = plan

  values = {
    arn    = "arn:aws:kms:us-east-1:916491575487:key/00000000-0000-0000-0000-000000000000"
    key_id = "00000000-0000-0000-0000-000000000000"
  }
}

override_module {
  target = module.vpc
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
  name                 = "microtodosuite-egress"
  aws_region           = "us-east-1"
  expected_account_id  = "916491575487"
  vpc_cidr             = "10.50.0.0/16"
  availability_zones   = ["us-east-1a"]
  public_subnet_cidrs  = ["10.50.0.0/24"]
  private_subnet_cidrs = ["10.50.16.0/20"]

  spokes = {
    "full-dev"     = { vpc_cidr = "10.40.0.0/16" }
    "full-staging" = { vpc_cidr = "10.20.0.0/16" }
    "full-prod"    = { vpc_cidr = "10.30.0.0/16" }
  }

  tags = {
    Project = "MicroTodoSuite"
  }
}

# One shared egress path. A second NAT gateway or a second Elastic IP is the
# specific cost and quota regression this stage exists to prevent.
run "single_nat_gateway_behind_a_single_elastic_ip" {
  command = plan

  assert {
    condition     = output.egress_contract.nat.enabled == true
    error_message = "The egress hub must create a NAT gateway; it is the only path off-network for every spoke."
  }

  assert {
    condition     = output.egress_contract.nat.single == true
    error_message = "The egress hub must use exactly one NAT gateway, not one per availability zone."
  }

  assert {
    condition     = output.egress_contract.nat.one_per_az == false
    error_message = "one_nat_gateway_per_az would create one Elastic IP per AZ and defeat the single-EIP budget."
  }

  assert {
    condition     = output.egress_contract.nat.gateway_count == 1
    error_message = "Exactly one NAT gateway must exist in the hub."
  }

  assert {
    condition     = output.egress_contract.nat.elastic_ip_count == 1
    error_message = "Exactly one Elastic IP must exist in the hub, so a spoke's outbound allowlist stays a single address."
  }

  assert {
    condition     = output.egress_contract.availability_zone_count == 1
    error_message = "The reviewed egress topology is deliberately single-AZ; widening it is a cost and availability decision, not a default."
  }
}

# The transit gateway must not associate or propagate anything by default.
# Default association is precisely how a new spoke would silently gain a route
# to every other spoke.
run "transit_gateway_never_associates_or_propagates_by_default" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable"
    error_message = "Default route table association must be disabled so a new attachment cannot inherit routes to other spokes."
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "Default route table propagation must be disabled so a spoke CIDR cannot be advertised to other spokes."
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.auto_accept_shared_attachments == "disable"
    error_message = "Attachments must be explicitly accepted; auto-accept would let an unreviewed VPC join the hub."
  }
}

# One route table per spoke, each distinct. A shared route table would put every
# spoke's routes in one place and make spoke-to-spoke reachability a one-line
# change.
run "each_spoke_gets_its_own_dedicated_route_table" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.spoke) == length(var.spokes)
    error_message = "Every declared spoke must get exactly one dedicated transit gateway route table."
  }

  assert {
    condition = alltrue([
      for key in keys(var.spokes) : contains(keys(aws_ec2_transit_gateway_route_table.spoke), key)
    ])
    error_message = "A spoke route table must be keyed by the spoke name so a spoke can find its own table without guessing."
  }

  assert {
    condition = alltrue([
      for table in values(aws_ec2_transit_gateway_route_table.spoke) :
      table.transit_gateway_id == aws_ec2_transit_gateway.this.id
    ])
    error_message = "All spoke route tables must belong to this hub's single transit gateway."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table.egress.transit_gateway_id == aws_ec2_transit_gateway.this.id
    error_message = "The hub needs its own route table, separate from every spoke table, to hold spoke return routes."
  }
}

# The hub creates the spoke route tables empty. Everything that makes a specific
# spoke reachable is the spoke's own resource in the spoke's own state, so no
# spoke can route itself to a neighbour by editing hub state.
run "hub_owns_no_spoke_attachment_and_no_spoke_route" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.egress) == 1
    error_message = "The hub attaches only its own egress VPC."
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.egress[0].vpc_id == module.vpc.vpc_id
    error_message = "The hub's only attachment must be its own egress VPC."
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.egress[0].transit_gateway_default_route_table_association == false
    error_message = "Even the hub's own attachment must not fall back to the default route table."
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.egress[0].transit_gateway_default_route_table_propagation == false
    error_message = "The egress VPC CIDR must not be propagated into the default route table."
  }

  assert {
    condition     = output.egress_contract.hub_owned_spoke_attachment_count == 0
    error_message = "A spoke attachment belongs to the spoke's own state, never to the hub."
  }

  assert {
    condition     = output.egress_contract.hub_owned_spoke_transit_route_count == 0
    error_message = "The hub must create every spoke transit gateway route table empty; spoke default and return routes are spoke-owned."
  }

  assert {
    condition     = output.egress_contract.spokes.cross_spoke_routes == 0
    error_message = "No spoke route table may contain a route toward another spoke's attachment."
  }

  # The hub's own VPC route table is the one place it must name spoke CIDRs: a
  # NAT reply is translated back to the spoke's private address and has to be
  # routed out of the public subnet. These point at the transit gateway, never
  # at a spoke attachment, so they carry no spoke-to-spoke path.
  assert {
    condition     = output.egress_contract.hub_vpc_return_route_count == length(var.spokes)
    error_message = "The hub needs exactly one VPC return route per spoke; without them every spoke's outbound connection hangs on the reply instead of failing cleanly."
  }

  assert {
    condition = alltrue([
      for route in values(aws_route.spoke_return) :
      route.transit_gateway_id == aws_ec2_transit_gateway.this.id && route.nat_gateway_id == null
    ])
    error_message = "A hub return route must point at the transit gateway, never at a specific spoke attachment or back at the NAT gateway."
  }

  assert {
    condition = length(distinct([
      for route in values(aws_route.spoke_return) : route.destination_cidr_block
    ])) == length(var.spokes)
    error_message = "Each spoke must get its own distinct return route destination."
  }
}

# Flow logs are the only record of what actually crossed the shared boundary,
# so they must exist and be encrypted with a key this module owns and rotates.
run "flow_logs_are_encrypted_with_a_rotating_customer_managed_key" {
  command = plan

  assert {
    condition     = output.egress_contract.flow_logs.enabled == true
    error_message = "The shared egress boundary must record flow logs."
  }

  assert {
    condition     = output.egress_contract.flow_logs.kms_key_arn == aws_kms_key.flow_logs.arn
    error_message = "Flow logs must be encrypted with this module's customer-managed key, not an AWS-managed default."
  }

  assert {
    condition     = aws_kms_key.flow_logs.enable_key_rotation == true
    error_message = "The flow-log key must rotate."
  }

  assert {
    condition     = output.egress_contract.flow_logs.traffic_type == "ALL"
    error_message = "Rejected traffic is the evidence that isolation held, so ALL traffic must be logged."
  }
}

# A spoke consumes the hub purely through these outputs. A missing one leaves
# the spoke unable to attach itself, which is the failure this asserts against.
run "outputs_expose_exactly_what_a_spoke_needs_to_attach_itself" {
  command = plan

  assert {
    condition     = output.transit_gateway_id == aws_ec2_transit_gateway.this.id
    error_message = "A spoke needs the transit gateway id to create its own attachment."
  }

  assert {
    condition     = output.egress_contract.transit_gateway.id == aws_ec2_transit_gateway.this.id
    error_message = "The reviewable contract must report the same transit gateway a spoke is told to attach to."
  }

  assert {
    condition = alltrue([
      for key in keys(var.spokes) : contains(keys(output.spoke_route_table_ids), key)
    ])
    error_message = "Each spoke needs its own route table id to associate its own attachment."
  }

  assert {
    condition     = length(output.spoke_route_table_ids) == length(var.spokes)
    error_message = "The hub must publish exactly one route table per declared spoke and no extras."
  }

  assert {
    condition     = length(output.egress_public_ips) == 1
    error_message = "The hub must report exactly one egress public IP so a downstream allowlist stays a single value."
  }

  assert {
    condition     = output.egress_contract.spokes.declared_cidrs == { for key, spoke in var.spokes : key => spoke.vpc_cidr }
    error_message = "The contract must report the exact spoke CIDRs it routed, so a review can compare them against the approved plan."
  }
}

# A spoke CIDR that overlaps another spoke, or the hub itself, makes routing
# ambiguous and silently breaks isolation. Reject it while planning rather than
# discovering it from a black-hole route after apply.
run "overlapping_spoke_cidrs_are_rejected" {
  command = plan

  variables {
    spokes = {
      "full-dev"  = { vpc_cidr = "10.40.0.0/16" }
      "full-prod" = { vpc_cidr = "10.40.128.0/17" }
    }
  }

  expect_failures = [
    var.spokes,
  ]
}

run "spoke_cidr_overlapping_the_hub_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.40.0.0/16"
    spokes = {
      "full-dev" = { vpc_cidr = "10.40.0.0/16" }
    }
  }

  expect_failures = [
    var.spokes,
  ]
}
