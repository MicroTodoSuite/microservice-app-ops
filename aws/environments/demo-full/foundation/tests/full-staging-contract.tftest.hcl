# demo-full is the live full staging environment. It is the one root in this
# stage that already exists in AWS, so this file is a regression test before it
# is a feature test.
#
# The first run block pins what is running today. If enabling the full-profile
# opt-ins were to change the address space, the NAT count, or the bootstrap node
# count, that would replace physical staging resources rather than add to them —
# so those values are asserted against the current reality first, and the opt-in
# behaviour is asserted separately.

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

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_service_principal" {
    defaults = {
      name = "ec2.amazonaws.com"
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:916491575487:secret:microtodosuite/staging/auth-api-secrets-AbCdEf"
      id  = "arn:aws:secretsmanager:us-east-1:916491575487:secret:microtodosuite/staging/auth-api-secrets-AbCdEf"
    }
  }
}

override_module {
  target = module.foundation.module.vpc
  outputs = {
    vpc_id          = "vpc-0demofull00000000"
    public_subnets  = ["subnet-df-public-a", "subnet-df-public-b", "subnet-df-public-c"]
    private_subnets = ["subnet-df-private-a", "subnet-df-private-b", "subnet-df-private-c"]

    private_route_table_ids = ["rtb-df-private-a", "rtb-df-private-b", "rtb-df-private-c"]
    public_route_table_ids  = ["rtb-df-public"]

    # One shared NAT gateway: the existing cost-reduced staging exception.
    natgw_ids      = ["nat-df-a"]
    nat_ids        = ["eipalloc-df-a"]
    nat_public_ips = ["203.0.113.20"]

    vpc_flow_log_id              = "fl-0demofull00000000"
    vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:916491575487:log-group:/aws/vpc-flow-logs/microtodosuite-demo-full"
  }
}

override_module {
  target = module.foundation.module.eks
  outputs = {
    cluster_name                       = "microtodosuite-demo-full"
    cluster_arn                        = "arn:aws:eks:us-east-1:916491575487:cluster/microtodosuite-demo-full"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_service_cidr               = "172.20.0.0/16"
    cluster_primary_security_group_id  = "sg-primary"
    node_security_group_id             = "sg-node"
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/demofull"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/demofull"
    oidc_provider_arn                  = "arn:aws:iam::916491575487:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/demofull"
  }
}

override_module {
  target = module.foundation.module.bootstrap_node_group
  outputs = {
    node_group_id     = "microtodosuite-demo-full:bootstrap"
    node_group_arn    = "arn:aws:eks:us-east-1:916491575487:nodegroup/microtodosuite-demo-full/bootstrap/test"
    node_group_status = "ACTIVE"
  }
}

# TEST-NET-1 stand-ins for the four reviewed operator addresses, which live only
# in the gitignored tfvars. The assertions check the allowlist's shape — four
# entries, all host routes, no wildcard — rather than committing real operator
# addresses to a tracked file.
variables {
  environment                    = "demo-full"
  expected_account_id            = "916491575487"
  aws_region                     = "us-east-1"
  bootstrap_admin_principal_arns = ["arn:aws:iam::916491575487:role/microtodosuite-terraform-dev"]
  single_nat_gateway             = true

  # The reviewed staging allocation, matching demo-full.tfvars.example.
  availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c"]
  vpc_cidr                = "10.20.0.0/16"
  public_subnet_cidrs     = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs    = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
  create_shared_resources = false
  shared_environments     = []

  cluster_public_access_cidrs = [
    "192.0.2.10/32",
    "192.0.2.11/32",
    "192.0.2.12/32",
    "192.0.2.13/32",
  ]
}

# ---------------------------------------------------------------------------
# Regression: what staging runs today, before any opt-in.
# ---------------------------------------------------------------------------

run "current_staging_topology_is_unchanged_by_default" {
  command = plan

  assert {
    condition     = var.vpc_cidr == "10.20.0.0/16"
    error_message = "demo-full occupies 10.20.0.0/16. Changing it would replace the live staging VPC, not adjust it."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_count == 1
    error_message = "Staging runs on one shared NAT gateway; a second would be new spend and a new Elastic IP against the fleet quota."
  }

  assert {
    condition     = output.foundation_contract.network.outbound_mode == "direct-nat"
    error_message = "Staging keeps its own in-VPC NAT egress. Moving it onto the shared hub would rewrite the live default route of a running environment."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.desired == 2
    error_message = "Staging bootstraps on two nodes today; changing the count here would resize a live node group."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.min == 2 && output.foundation_contract.eks.node_group.max == 4
    error_message = "The live staging bootstrap group is 2/2/4."
  }
}

# The opt-ins must be off unless a tfvars file turns them on, so that a plan of
# the unchanged root produces no additions.
run "full_profile_prerequisites_are_off_by_default" {
  command = plan

  assert {
    condition     = var.enable_full_profile_cluster_prerequisites == false
    error_message = "The prerequisites must default off so an unchanged demo-full plan stays empty."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.enabled == false
    error_message = "Default-on prerequisites would add IAM roles and a queue to a live environment without anyone asking."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.karpenter_controller_role_arn == null
    error_message = "No Karpenter role may exist until staging explicitly opts in."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.aws_load_balancer_controller_role_arn == null
    error_message = "No load balancer controller role may exist until staging explicitly opts in."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.karpenter_interruption_rule_count == 0
    error_message = "No interruption rules may exist until staging explicitly opts in."
  }

  # Enforcement of NetworkPolicy is an unconditional baseline, not an opt-in: a
  # cluster carrying NetworkPolicy objects that nothing enforces looks isolated
  # in Git while being flat in reality.
  assert {
    condition     = output.foundation_contract.cluster_prerequisites.vpc_cni_network_policy_enabled == true
    error_message = "NetworkPolicy enforcement is a baseline in both profiles, including staging today."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.ebs_csi_driver == true
    error_message = "The EBS CSI driver is a baseline in both profiles; Kubernetes 1.35 has no in-tree provisioner."
  }
}

run "control_plane_allowlist_is_exactly_four_reviewed_host_routes" {
  command = plan

  assert {
    condition     = output.foundation_contract.eks.public_access_cidr_count == 4
    error_message = "Exactly four reviewed operator addresses are approved for staging's control plane endpoint."
  }

  assert {
    condition = alltrue([
      for cidr in output.foundation_contract.eks.public_access_cidrs : endswith(cidr, "/32")
    ])
    error_message = "Every operator entry must be a single host route."
  }

  assert {
    condition     = output.foundation_contract.eks.public_access_is_wildcard == false
    error_message = "0.0.0.0/0 would expose staging's API server while endpoint_public_access still looked correct."
  }

  assert {
    condition     = output.foundation_contract.eks.endpoint_private_access == true
    error_message = "In-VPC callers must reach the API server privately."
  }
}

run "staging_stays_a_consumer_and_creates_no_shared_resource" {
  command = plan

  assert {
    condition     = output.foundation_contract.shared_resources.owned == false
    error_message = "demo-full is a consumer; the dev owner root owns every shared resource."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.neutral_ecr_repositories_created == 0
    error_message = "The environment-neutral ECR repositories are shared and must only be referenced here."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.github_oidc_providers_created == 0
    error_message = "The GitHub OIDC provider is an account-level singleton."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.jwt_secret_containers_created == 0
    error_message = "A consumer creates zero secret containers."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.jwt_owner_reader_roles_created == 0
    error_message = "The per-environment owner readers belong to the owner root."
  }
}

# ---------------------------------------------------------------------------
# Opt-in: what staging becomes when the full-profile inputs are turned on.
# Every assertion above about address space, NAT count, and bootstrap size is
# repeated here, because the whole point is that opting in adds capability
# without touching the live topology.
# ---------------------------------------------------------------------------

run "opting_in_adds_prerequisites_without_touching_live_topology" {
  command = plan

  variables {
    enable_full_profile_cluster_prerequisites = true
    aws_load_balancer_controller_policy_arns = [
      "arn:aws:iam::916491575487:policy/AWSLoadBalancerControllerIAMPolicy",
    ]
    consumer_jwt_environment = "staging"
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.enabled == true
    error_message = "The explicit opt-in must enable the prerequisites."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.karpenter_interruption_rule_count > 0
    error_message = "Karpenter must get its interruption rules, or it learns about a reclaimed node only when it stops responding."
  }

  # The live topology must be identical to the default run above. A difference
  # in any of these means the opt-in replaces staging rather than extending it.
  assert {
    condition     = output.foundation_contract.network.nat_gateway_count == 1
    error_message = "Opting in must not add a NAT gateway to a live environment."
  }

  assert {
    condition     = output.foundation_contract.network.outbound_mode == "direct-nat"
    error_message = "Opting in must not move live staging onto the shared egress hub."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.desired == 2
    error_message = "Opting in must not resize the live bootstrap node group."
  }

  assert {
    condition     = var.vpc_cidr == "10.20.0.0/16"
    error_message = "Opting in must not move staging's address space."
  }
}

run "opting_in_grants_exactly_one_cluster_qualified_staging_reader" {
  command = plan

  variables {
    enable_full_profile_cluster_prerequisites = true
    aws_load_balancer_controller_policy_arns = [
      "arn:aws:iam::916491575487:policy/AWSLoadBalancerControllerIAMPolicy",
    ]
    consumer_jwt_environment = "staging"
  }

  assert {
    condition     = output.foundation_contract.consumer_jwt.reader_count == 1
    error_message = "Staging needs exactly one reader: zero leaves External Secrets unable to resolve the secret, more than one is an extra unreviewed path to it."
  }

  assert {
    condition     = output.foundation_contract.consumer_jwt.environment == "staging"
    error_message = "The staging cluster reads the staging JWT secret only; dev or prod would cross an environment boundary."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.jwt_secret_containers_created == 0
    error_message = "Reading the owner's secret must not create a second copy of it."
  }
}

run "a_wildcard_operator_cidr_is_rejected" {
  command = plan

  variables {
    cluster_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [
    var.cluster_public_access_cidrs,
  ]
}

run "becoming_a_shared_resource_owner_is_rejected" {
  command = plan

  variables {
    create_shared_resources = true
  }

  expect_failures = [
    var.create_shared_resources,
  ]
}
