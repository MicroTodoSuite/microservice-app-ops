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
}

override_module {
  target = module.vpc
  outputs = {
    vpc_id                       = "vpc-0123456789abcdef0"
    public_subnets               = ["subnet-public-a", "subnet-public-b", "subnet-public-c"]
    private_subnets              = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
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
    condition     = aws_eks_addon.vpc_cni.addon_version == "v1.23.0-eksbuild.1" && aws_eks_addon.coredns.addon_version == "v1.14.3-eksbuild.3" && aws_eks_addon.kube_proxy.addon_version == "v1.35.3-eksbuild.18"
    error_message = "The three EKS managed add-ons must use the reviewed Kubernetes 1.35 versions."
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
