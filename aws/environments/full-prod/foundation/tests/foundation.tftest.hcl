# Contract for the full-profile production environment.
#
# Unlike the economical dev root's tests, these deliberately do NOT override
# module.foundation. Overriding it would replace the contract with a fixture and
# the assertions would then only prove that the fixture says what the fixture
# says. The nested VPC/EKS/node-group modules are overridden instead, so the
# real foundation logic runs against this root's real inputs and the resulting
# contract is genuinely computed.

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
      arn = "arn:aws:secretsmanager:us-east-1:916491575487:secret:microtodosuite/prod/auth-api-secrets-AbCdEf"
      id  = "arn:aws:secretsmanager:us-east-1:916491575487:secret:microtodosuite/prod/auth-api-secrets-AbCdEf"
    }
  }
}

override_module {
  target = module.foundation.module.vpc
  outputs = {
    vpc_id = "vpc-0fullprod00000000"
    # A transit-egress spoke keeps public subnets for load balancers only.
    public_subnets  = ["subnet-fp-public-a", "subnet-fp-public-b", "subnet-fp-public-c"]
    private_subnets = ["subnet-fp-private-a", "subnet-fp-private-b", "subnet-fp-private-c"]

    private_route_table_ids = ["rtb-fp-private-a", "rtb-fp-private-b", "rtb-fp-private-c"]
    public_route_table_ids  = ["rtb-fp-public"]

    # The point of transit egress: no NAT gateway, therefore no Elastic IP.
    natgw_ids      = []
    nat_ids        = []
    nat_public_ips = []

    vpc_flow_log_id              = "fl-0fullprod00000000"
    vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:916491575487:log-group:/aws/vpc-flow-logs/microtodosuite-full-prod"
  }
}

override_module {
  target = module.foundation.module.eks
  outputs = {
    cluster_name                       = "microtodosuite-full-prod"
    cluster_arn                        = "arn:aws:eks:us-east-1:916491575487:cluster/microtodosuite-full-prod"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_service_cidr               = "172.20.0.0/16"
    cluster_primary_security_group_id  = "sg-primary"
    node_security_group_id             = "sg-node"
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/fullprod"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/fullprod"
    oidc_provider_arn                  = "arn:aws:iam::916491575487:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/fullprod"
  }
}

# The Karpenter submodule's role ARNs are computed too. Overriding it here means
# the interruption-rule count below comes from this fixture rather than from the
# real submodule, so the authoritative check on Karpenter's own wiring stays in
# aws/modules/environment-foundation/tests/network_eks.tftest.hcl. What this root
# test still proves is that the root turns Karpenter on at all.
override_module {
  target = module.foundation.module.karpenter[0]

  outputs = {
    iam_role_arn          = "arn:aws:iam::916491575487:role/microtodosuite-full-prod-karpenter"
    node_iam_role_arn     = "arn:aws:iam::916491575487:role/microtodosuite-full-prod-karpenter-node"
    node_iam_role_name    = "microtodosuite-full-prod-karpenter-node"
    instance_profile_name = "microtodosuite-full-prod-karpenter-node"
    queue_arn             = "arn:aws:sqs:us-east-1:916491575487:microtodosuite-full-prod-karpenter"
    queue_name            = "microtodosuite-full-prod-karpenter"
    queue_url             = "https://sqs.us-east-1.amazonaws.com/916491575487/microtodosuite-full-prod-karpenter"

    event_rules = {
      spot_interruption     = { name = "spot-interruption" }
      rebalance             = { name = "rebalance" }
      instance_state_change = { name = "instance-state-change" }
      scheduled_change      = { name = "scheduled-change" }
    }
  }
}

# IAM role ARNs are computed, so "the role exists" cannot be evaluated during a
# plan unless the ARN is pinned. Pinning keeps this assertion in `plan`, where it
# runs on every change, rather than demoting it to an `apply` against real AWS.
override_resource {
  target          = module.foundation.aws_iam_role.aws_load_balancer_controller[0]
  override_during = plan

  values = {
    arn = "arn:aws:iam::916491575487:role/microtodosuite-full-prod-aws-load-balancer-controller"
  }
}

override_resource {
  target          = module.foundation.aws_iam_role.consumer_jwt_reader[0]
  override_during = plan

  values = {
    arn = "arn:aws:iam::916491575487:role/microtodosuite-full-prod-prod-jwt-reader"
  }
}

override_module {
  target = module.foundation.module.bootstrap_node_group
  outputs = {
    node_group_id     = "microtodosuite-full-prod:bootstrap"
    node_group_arn    = "arn:aws:eks:us-east-1:916491575487:nodegroup/microtodosuite-full-prod/bootstrap/test"
    node_group_status = "ACTIVE"
  }
}

# TEST-NET-1 stand-ins. The real operator addresses live only in the gitignored
# tfvars, which is why these assertions check the shape of the allowlist —
# exactly four host routes, no wildcard — rather than hardcoding home IP
# addresses into a tracked file. The exact values are compared against the
# approved plan at apply time.
variables {
  expected_account_id = "916491575487"
  transit_gateway_id  = "tgw-0123456789abcdef0"

  cluster_public_access_cidrs = [
    "192.0.2.10/32",
    "192.0.2.11/32",
    "192.0.2.12/32",
    "192.0.2.13/32",
  ]

  bootstrap_admin_principal_arns = ["arn:aws:iam::916491575487:role/microtodosuite-terraform-dev"]

  aws_load_balancer_controller_policy_arns = [
    "arn:aws:iam::916491575487:policy/AWSLoadBalancerControllerIAMPolicy",
  ]
}

run "identity_region_and_address_space_match_the_reviewed_allocation" {
  command = plan

  assert {
    condition     = var.expected_account_id == "916491575487"
    error_message = "full-prod belongs to the single reviewed AWS account."
  }

  assert {
    condition     = var.aws_region == "us-east-1"
    error_message = "full-prod must be in us-east-1, the region of the shared egress hub it depends on."
  }

  assert {
    condition     = var.vpc_cidr == "10.30.0.0/16"
    error_message = "full-prod owns 10.30.0.0/16. Any other range risks colliding with a sibling environment on the shared transit gateway."
  }

  assert {
    condition     = output.foundation_contract.environment == "full-prod"
    error_message = "The root must build the full-prod environment and nothing else."
  }
}

# Transit egress is the property that makes this environment cheap to run
# alongside the others: no NAT gateway of its own, no Elastic IP of its own.
run "private_workloads_leave_through_the_shared_hub_not_a_local_nat" {
  command = plan

  assert {
    condition     = output.foundation_contract.network.outbound_mode == "transit-egress"
    error_message = "full-prod must use the shared egress hub."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_enabled == false
    error_message = "A transit-egress spoke must not create its own NAT gateway."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_count == 0
    error_message = "full-prod must consume zero NAT gateways and therefore zero Elastic IPs; the EIP quota is the binding constraint across the fleet."
  }

  assert {
    condition     = output.foundation_contract.network.transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "full-prod must point at the reviewed shared transit gateway."
  }

  assert {
    condition     = output.foundation_contract.network.transit_egress_route_count == length(var.private_subnet_cidrs)
    error_message = "Every private route table needs its own default route to the transit gateway, or the workers on that table come up with no path off-VPC."
  }
}

# A one-node bootstrap group. Everything beyond it is Karpenter's job, so a
# larger managed group here is silent duplicated spend.
run "bootstrap_capacity_is_a_single_node" {
  command = plan

  assert {
    condition     = output.foundation_contract.eks.node_group.desired == 1
    error_message = "full-prod bootstraps on exactly one node; Karpenter provisions everything after that."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.min == 1
    error_message = "The bootstrap group's floor must be one node."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.capacity_type == "ON_DEMAND"
    error_message = "The bootstrap node carries the cluster's control-plane add-ons; a Spot interruption there takes the cluster's own scheduler with it."
  }
}

# The control plane must be reachable privately, and publicly only from the
# reviewed operator addresses.
run "control_plane_is_private_with_exactly_four_reviewed_host_routes" {
  command = plan

  assert {
    condition     = output.foundation_contract.eks.endpoint_private_access == true
    error_message = "In-cluster and in-VPC callers must reach the API server privately."
  }

  assert {
    condition     = output.foundation_contract.eks.public_access_cidr_count == 4
    error_message = "Exactly four reviewed operator addresses may reach the public endpoint."
  }

  assert {
    condition = alltrue([
      for cidr in output.foundation_contract.eks.public_access_cidrs : endswith(cidr, "/32")
    ])
    error_message = "Every operator entry must be a single host route; a wider prefix admits addresses nobody reviewed."
  }

  assert {
    condition     = output.foundation_contract.eks.public_access_is_wildcard == false
    error_message = "0.0.0.0/0 on the control plane endpoint would leave endpoint_public_access looking correct while exposing the API server to the internet."
  }
}

run "full_profile_cluster_prerequisites_are_enabled" {
  command = plan

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.enabled == true
    error_message = "full-prod is a full-profile environment and must enable its cluster prerequisites."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.ebs_csi_driver == true
    error_message = "Kubernetes 1.35 has no in-tree EBS provisioner; without the CSI driver every PVC stays pending."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.karpenter_controller_role_arn != null
    error_message = "Karpenter needs its controller IRSA role to scale the cluster past the single bootstrap node."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.karpenter_interruption_rule_count > 0
    error_message = "Without interruption rules Karpenter learns about a reclaimed node only when it stops responding."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.aws_load_balancer_controller_role_arn != null
    error_message = "The load balancer controller needs its IRSA role to create ingress load balancers."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.vpc_cni_network_policy_enabled == true
    error_message = "NetworkPolicy objects that nothing enforces leave the cluster flat while looking isolated in Git."
  }
}

# Consumer mode. Shared resources belong to the dev owner root; a consumer that
# creates its own would produce a second, competing copy of a global singleton.
run "consumer_mode_creates_no_shared_resource_and_no_secret" {
  command = plan

  assert {
    condition     = var.create_shared_resources == false
    error_message = "full-prod is a consumer environment; the dev owner root owns every shared resource."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.owned == false
    error_message = "full-prod must report itself as a consumer, not an owner, of the shared resources."
  }

  # Counting managed resources, not reading ARNs. Several shared resources have
  # a data-source twin, so a consumer still reports a non-null ARN for something
  # it only looked up; only the created count separates owning from reading.
  assert {
    condition     = output.foundation_contract.shared_resources.neutral_ecr_repositories_created == 0
    error_message = "The environment-neutral ECR repositories are shared; a consumer must reference them, never create a competing set."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.github_oidc_providers_created == 0
    error_message = "The GitHub OIDC provider is an account-level singleton. A second one would silently split the trust surface."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.github_publisher_roles_created == 0
    error_message = "The release publisher role is owned by the dev root."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.kyverno_verifier_roles_created == 0
    error_message = "The Kyverno image verifier role is shared and owned by the dev root."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.jwt_secret_containers_created == 0
    error_message = "A consumer creates zero JWT secret containers; it reads the owner's."
  }

  assert {
    condition     = output.foundation_contract.shared_resources.jwt_owner_reader_roles_created == 0
    error_message = "The per-environment owner readers belong to the owner root."
  }

  assert {
    condition     = length(output.environment_jwt_secret_names) == 0
    error_message = "A consumer environment must expose no secret containers of its own."
  }

  # Its own per-environment repositories are expected and are not shared: each is
  # named project/environment/service, so two environments cannot collide.
  assert {
    condition     = output.foundation_contract.shared_resources.environment_ecr_repositories_created == 5
    error_message = "The environment keeps its own five per-environment repositories; these are namespaced and collide with nothing."
  }
}

# Exactly one reader, qualified by this cluster, reaching exactly one
# environment's secret.
run "exactly_one_cluster_qualified_prod_jwt_reader" {
  command = plan

  # Counted, not null-checked: zero readers leaves External Secrets unable to
  # resolve the secret, and more than one is an extra unreviewed path to it.
  assert {
    condition     = output.foundation_contract.consumer_jwt.reader_count == 1
    error_message = "full-prod needs exactly one reader for the prod JWT secret."
  }

  assert {
    condition     = output.foundation_contract.consumer_jwt.environment == "prod"
    error_message = "full-prod reads the prod JWT secret; reading dev or staging would cross an environment boundary."
  }

  assert {
    condition     = output.consumer_jwt_reader_role_arn != null
    error_message = "The reader ARN must be published so the GitOps SecretStore can assume it."
  }
}

run "a_wrong_account_is_rejected" {
  command = plan

  variables {
    expected_account_id = "123456789012"
  }

  expect_failures = [
    var.expected_account_id,
  ]
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

run "transit_egress_without_a_transit_gateway_is_rejected" {
  command = plan

  variables {
    transit_gateway_id = null
  }

  expect_failures = [
    var.transit_gateway_id,
  ]
}
