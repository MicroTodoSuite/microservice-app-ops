mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/test"
      id         = "123456789012"
      user_id    = "test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  # The vendored Karpenter submodule renders its IAM through
  # aws_iam_policy_document. Only the computed `json` attribute is mocked, so
  # every statement this module actually configures stays assertable while the
  # nested module still receives parseable JSON.
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
}

override_module {
  target = module.vpc
  outputs = {
    vpc_id                       = "vpc-0123456789abcdef0"
    public_subnets               = ["subnet-public-a", "subnet-public-b", "subnet-public-c"]
    private_subnets              = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
    private_route_table_ids      = ["rtb-private-a", "rtb-private-b", "rtb-private-c"]
    public_route_table_ids       = ["rtb-public"]
    natgw_ids                    = ["nat-a", "nat-b", "nat-c"]
    vpc_flow_log_id              = "fl-0123456789abcdef0"
    vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/microtodosuite-dev"
  }
}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "microtodosuite-dev"
    cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/microtodosuite-dev"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_service_cidr               = "172.20.0.0/16"
    cluster_primary_security_group_id  = "sg-primary"
    node_security_group_id             = "sg-node"
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/test"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/test"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/test"
  }
}

override_module {
  target = module.bootstrap_node_group
  outputs = {
    node_group_id     = "microtodosuite-dev:bootstrap"
    node_group_arn    = "arn:aws:eks:us-east-1:123456789012:nodegroup/microtodosuite-dev/bootstrap/test"
    node_group_status = "ACTIVE"
  }
}

variables {
  environment         = "dev"
  shared_environments = ["dev", "staging", "prod"]
  environment_jwt_values = {
    dev     = "mock-dev-jwt-value"
    staging = "mock-staging-jwt-value"
    prod    = "mock-prod-jwt-value"
  }
}

run "network_and_eks_contract" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_instance_types  = ["m7i-flex.large"]
  }

  assert {
    condition     = output.foundation_contract.environment == "dev"
    error_message = "The foundation must remain dev-only."
  }

  assert {
    condition     = output.foundation_contract.network.az_count == 3
    error_message = "The VPC must span exactly three selected availability zones."
  }

  assert {
    condition     = output.foundation_contract.network.private_worker_subnet_count == 3 && output.foundation_contract.network.public_subnet_count == 3
    error_message = "The VPC must have one public/private subnet pair per AZ."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_count == 3
    error_message = "The full profile must retain one NAT gateway per AZ."
  }

  assert {
    condition     = output.foundation_contract.eks.kubernetes_version == "1.35"
    error_message = "EKS must remain pinned to Kubernetes 1.35."
  }

  assert {
    condition     = output.foundation_contract.eks.endpoint_private_access && output.foundation_contract.eks.endpoint_public_access
    error_message = "EKS must expose private API access and explicitly allowlisted public API access."
  }

  assert {
    condition     = output.foundation_contract.eks.node_group == { min = 2, desired = 2, max = 4, capacity_type = "ON_DEMAND", ami_type = "AL2023_x86_64_STANDARD" }
    error_message = "Bootstrap nodes must use the approved stable managed-node configuration."
  }

  assert {
    condition     = aws_eks_addon.vpc_cni.addon_version == "v1.23.0-eksbuild.1" && aws_eks_addon.coredns.addon_version == "v1.14.3-eksbuild.3" && aws_eks_addon.kube_proxy.addon_version == "v1.35.3-eksbuild.18" && aws_eks_addon.ebs_csi.addon_version == "v1.64.0-eksbuild.1"
    error_message = "The four EKS managed add-ons must use the reviewed Kubernetes 1.35 versions."
  }

  assert {
    condition     = try(jsondecode(aws_eks_addon.vpc_cni.configuration_values).enableNetworkPolicy == "true", false)
    error_message = "The VPC CNI managed add-on must declaratively enable its network-policy node agent."
  }

  assert {
    condition     = try(jsondecode(aws_eks_addon.vpc_cni.configuration_values).env.ENABLE_PREFIX_DELEGATION == "true", false)
    error_message = "The VPC CNI managed add-on must enable prefix delegation to raise max pods per node without additional EC2 spend."
  }
}

run "reject_burstable_free_tier_shortcut" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_instance_types  = ["t3.small"]
  }

  expect_failures = [var.bootstrap_node_instance_types]
}

run "reject_account_ineligible_instance_type" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_instance_types  = ["m7i.large"]
  }

  expect_failures = [var.bootstrap_node_instance_types]
}

run "accept_environment_specific_api_narrowing" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }
}

run "reject_invalid_api_cidr" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["not-a-cidr"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  expect_failures = [var.cluster_public_access_cidrs]
}

run "reject_cross_account_administrator" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::111122223333:role/platform-admin"]
  }

  expect_failures = [var.bootstrap_admin_principal_arns]
}

# ---------------------------------------------------------------------------
# Full-profile network and cluster-prerequisite contract (spec 009, T011).
#
# These runs describe the generalized surface the full profile needs. Every new
# switch defaults off, so the economical dev and demo foundations keep their
# current inputs, resource set, and plan.
#
# The EBS CSI driver is deliberately NOT gated here: it became an unconditional
# baseline requirement for both profiles in PR #21, because the in-tree AWS EBS
# provisioner no longer exists on Kubernetes 1.35 and the economical profile's
# own Prometheus/Grafana volumes depend on it.
# ---------------------------------------------------------------------------

run "full_profile_switches_default_off" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition     = var.outbound_mode == "direct-nat"
    error_message = "outbound_mode must default to direct-nat so existing foundations keep in-VPC NAT egress."
  }

  assert {
    condition     = var.enable_full_profile_cluster_prerequisites == false
    error_message = "enable_full_profile_cluster_prerequisites must default off."
  }

  assert {
    condition     = var.transit_gateway_id == null
    error_message = "transit_gateway_id must default to null for direct-nat foundations."
  }

  assert {
    condition = (
      var.bootstrap_node_min_size == 2 &&
      var.bootstrap_node_desired_size == 2 &&
      var.bootstrap_node_max_size == 4
    )
    error_message = "Generalizing the bootstrap bounds must not change the current dev/demo defaults."
  }

  assert {
    condition     = length(module.karpenter) == 0
    error_message = "No Karpenter identity or interruption plumbing may exist while the prerequisite switch is off."
  }

  assert {
    condition     = length(aws_iam_role.aws_load_balancer_controller) == 0
    error_message = "No AWS Load Balancer Controller role may exist while the prerequisite switch is off."
  }

  assert {
    condition     = length(aws_route.private_transit_egress) == 0
    error_message = "A direct-nat foundation must not create transit-gateway default routes."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.enabled == false
    error_message = "The reviewable contract must report full-profile prerequisites as disabled."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.ebs_csi_driver
    error_message = "The EBS CSI driver must stay an unconditional baseline for both profiles."
  }

  assert {
    condition     = output.foundation_contract.network.outbound_mode == "direct-nat"
    error_message = "The reviewable contract must report the direct-nat outbound mode."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_enabled
    error_message = "direct-nat foundations must keep their NAT gateways enabled."
  }

  assert {
    condition     = output.foundation_contract.network.map_public_ip_on_launch == false
    error_message = "Worker and public subnets must never auto-assign public IPv4 addresses."
  }

  assert {
    condition = output.foundation_contract.network.public_load_balancer_subnet_tags == {
      "kubernetes.io/cluster/microtodosuite-dev" = "shared"
      "kubernetes.io/role/elb"                   = "1"
    }
    error_message = "Public subnets must carry exactly the internet-facing load-balancer discovery tags."
  }

  assert {
    condition = output.foundation_contract.network.private_load_balancer_subnet_tags == {
      "kubernetes.io/cluster/microtodosuite-dev" = "shared"
      "kubernetes.io/role/internal-elb"          = "1"
    }
    error_message = "Private subnets must carry exactly the internal load-balancer discovery tags."
  }
}

run "full_profile_prerequisites_are_cluster_specific_when_enabled" {
  command = plan

  variables {
    expected_account_id                       = "123456789012"
    aws_region                                = "us-east-1"
    availability_zones                        = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                                  = "10.10.0.0/16"
    public_subnet_cidrs                       = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs                      = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs               = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns            = ["arn:aws:iam::123456789012:role/platform-admin"]
    enable_full_profile_cluster_prerequisites = true
    aws_load_balancer_controller_policy_arns  = ["arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy"]
  }

  assert {
    condition     = length(module.karpenter) == 1
    error_message = "Enabling the prerequisite switch must create the Karpenter identities."
  }

  assert {
    condition = (
      one(data.aws_iam_policy_document.karpenter_controller_irsa[0].statement).actions == toset(["sts:AssumeRoleWithWebIdentity"]) &&
      one(one(data.aws_iam_policy_document.karpenter_controller_irsa[0].statement).principals).type == "Federated"
    )
    error_message = "The Karpenter controller must trust this cluster's OIDC issuer through IRSA, not EKS Pod Identity."
  }

  assert {
    condition = jsonencode({
      for c in one(data.aws_iam_policy_document.karpenter_controller_irsa[0].statement).condition :
      c.variable => tolist(c.values)
      }) == jsonencode({
      "oidc.eks.us-east-1.amazonaws.com/id/test:aud" = ["sts.amazonaws.com"]
      "oidc.eks.us-east-1.amazonaws.com/id/test:sub" = ["system:serviceaccount:kube-system:karpenter"]
    })
    error_message = "The Karpenter controller trust must be bound to the exact kube-system/karpenter service account and audience."
  }

  assert {
    condition     = module.karpenter[0].queue_name == "microtodosuite-dev-karpenter"
    error_message = "The Karpenter interruption queue must be named per cluster, never shared between clusters."
  }

  assert {
    condition     = length(aws_kms_key.karpenter_interruption) == 1 && aws_kms_key.karpenter_interruption[0].enable_key_rotation
    error_message = "The Karpenter interruption queue must be encrypted with a rotating customer-managed key."
  }

  assert {
    condition     = length(module.karpenter[0].event_rules) >= 4
    error_message = "EventBridge must deliver spot interruption, rebalance, instance-state and scheduled-change events to the queue."
  }

  assert {
    condition     = aws_iam_role.aws_load_balancer_controller[0].name == "microtodosuite-dev-aws-load-balancer-controller"
    error_message = "The AWS Load Balancer Controller role must be named per cluster."
  }

  assert {
    condition     = output.foundation_contract.cluster_prerequisites.enabled
    error_message = "The reviewable contract must report full-profile prerequisites as enabled."
  }

  assert {
    condition     = output.aws_load_balancer_controller_discovery.vpc_id == "vpc-0123456789abcdef0" && output.aws_load_balancer_controller_discovery.cluster_name == "microtodosuite-dev"
    error_message = "The controller must receive VPC- and cluster-scoped discovery inputs."
  }
}

run "reject_load_balancer_prerequisite_without_reviewed_policy" {
  command = plan

  variables {
    expected_account_id                       = "123456789012"
    aws_region                                = "us-east-1"
    availability_zones                        = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                                  = "10.10.0.0/16"
    public_subnet_cidrs                       = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs                      = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs               = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns            = ["arn:aws:iam::123456789012:role/platform-admin"]
    enable_full_profile_cluster_prerequisites = true
    aws_load_balancer_controller_policy_arns  = []
  }

  expect_failures = [var.aws_load_balancer_controller_policy_arns]
}

run "transit_egress_spoke_has_no_nat_or_elastic_ip" {
  command = plan

  override_module {
    target = module.vpc
    outputs = {
      vpc_id                       = "vpc-0123456789abcdef0"
      public_subnets               = ["subnet-public-a", "subnet-public-b", "subnet-public-c"]
      private_subnets              = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
      private_route_table_ids      = ["rtb-private-a", "rtb-private-b", "rtb-private-c"]
      public_route_table_ids       = ["rtb-public"]
      natgw_ids                    = []
      nat_ids                      = []
      vpc_flow_log_id              = "fl-0123456789abcdef0"
      vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/microtodosuite-dev"
    }
  }

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.20.0.0/16"
    public_subnet_cidrs            = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    private_subnet_cidrs           = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    outbound_mode                  = "transit-egress"
    transit_gateway_id             = "tgw-0123456789abcdef0"
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_enabled == false
    error_message = "A transit-egress spoke must not create NAT gateways or their Elastic IPs."
  }

  assert {
    condition     = output.foundation_contract.network.nat_gateway_count == 0
    error_message = "A transit-egress spoke must report zero NAT gateways."
  }

  assert {
    condition     = length(aws_route.private_transit_egress) == 3
    error_message = "Every private route table must send its default route to the transit gateway."
  }

  assert {
    condition = alltrue([
      for route in aws_route.private_transit_egress :
      route.destination_cidr_block == "0.0.0.0/0" && route.transit_gateway_id == "tgw-0123456789abcdef0"
    ])
    error_message = "Private default routes must target the reviewed transit gateway."
  }

  assert {
    condition     = alltrue([for route in aws_route.private_transit_egress : route.nat_gateway_id == null])
    error_message = "A transit-egress private route must never fall back to a NAT gateway."
  }

  assert {
    condition     = output.foundation_contract.network.internet_gateway_serves_public_load_balancers
    error_message = "A transit-egress spoke keeps its own internet gateway for public load balancers only."
  }

  assert {
    condition     = length(terraform_data.transit_egress_ready) == 1 && length(terraform_data.private_egress_ready) == 0
    error_message = "Nodes must wait for the transit-gateway default routes before they launch, and a transit spoke must not use the NAT readiness gate."
  }
}

run "reject_transit_egress_without_transit_gateway" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.20.0.0/16"
    public_subnet_cidrs            = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    private_subnet_cidrs           = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    outbound_mode                  = "transit-egress"
  }

  expect_failures = [var.transit_gateway_id]
}

run "reject_transit_gateway_in_direct_nat_mode" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    transit_gateway_id             = "tgw-0123456789abcdef0"
  }

  expect_failures = [var.transit_gateway_id]
}

run "reject_unknown_outbound_mode" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    outbound_mode                  = "public-subnet-nodes"
  }

  expect_failures = [var.outbound_mode]
}

run "accept_single_node_bootstrap_bounds" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_min_size        = 1
    bootstrap_node_desired_size    = 1
    bootstrap_node_max_size        = 1
  }

  assert {
    condition     = output.foundation_contract.eks.node_group.min == 1 && output.foundation_contract.eks.node_group.desired == 1 && output.foundation_contract.eks.node_group.max == 1
    error_message = "A reviewed one-node bootstrap group must be expressible for a cost-bounded full-profile cluster."
  }
}

run "reject_zero_node_bootstrap_group" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_min_size        = 0
    bootstrap_node_desired_size    = 0
    bootstrap_node_max_size        = 0
  }

  expect_failures = [
    var.bootstrap_node_min_size,
    var.bootstrap_node_desired_size,
    var.bootstrap_node_max_size,
  ]
}

run "reject_unordered_bootstrap_bounds" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    bootstrap_node_min_size        = 3
    bootstrap_node_desired_size    = 2
    bootstrap_node_max_size        = 4
  }

  expect_failures = [terraform_data.eks_input_guard]
}
