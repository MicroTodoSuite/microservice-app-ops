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
  target = module.foundation
  outputs = {
    foundation_contract = {
      environment = "dev"
      network = {
        az_count                    = 3
        private_worker_subnet_count = 3
        public_subnet_count         = 3
        nat_gateway_count           = 3
      }
      eks = {
        kubernetes_version      = "1.35"
        endpoint_private_access = true
        endpoint_public_access  = true
        node_group = {
          min           = 2
          desired       = 2
          max           = 4
          capacity_type = "ON_DEMAND"
          ami_type      = "AL2023_x86_64_STANDARD"
        }
      }
      dns = {
        public_hosted_zone_name = "microtodosuite.abrdns.com"
      }
      ecr_service_count = 5
      identity_mode     = "IRSA"
    }
    public_hosted_zone_name = "microtodosuite.abrdns.com"
    public_hosted_zone_id   = "Z0123456789ABCDEF"
    public_hosted_zone_name_servers = [
      "ns-100.awsdns-10.com",
      "ns-200.awsdns-20.net",
      "ns-300.awsdns-30.org",
      "ns-400.awsdns-40.co.uk",
    ]
    vpc_id                = "vpc-0123456789abcdef0"
    cluster_name          = "microtodosuite-dev"
    cluster_arn           = "arn:aws:eks:us-east-1:123456789012:cluster/microtodosuite-dev"
    ecr_repository_urls   = { for service in ["auth-api", "todos-api", "users-api", "frontend", "log-message-processor"] : service => "123456789012.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/dev/${service}" }
    oidc_provider_arn     = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/test"
    vpc_cni_irsa_role_arn = "arn:aws:iam::123456789012:role/microtodosuite-dev-vpc-cni"
    node_role_arn         = "arn:aws:iam::123456789012:role/microtodosuite-dev-node"
  }
}

# ---------------------------------------------------------------------------
# Root full-profile compatibility contract (spec 009, T013).
#
# This root must be able to express a full-profile environment without being
# forked, while every full-profile switch stays at the value dev already uses.
# ---------------------------------------------------------------------------

variables {
  environment                    = "dev"
  expected_account_id            = "123456789012"
  aws_region                     = "us-east-1"
  public_hosted_zone_name        = "microtodosuite.abrdns.com"
  availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  vpc_cidr                       = "10.10.0.0/16"
  public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
  single_nat_gateway             = false
  cluster_public_access_cidrs    = ["0.0.0.0/0"]
  bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/microtodosuite-terraform-dev"]
  create_shared_resources        = true
  shared_environments            = ["dev", "staging", "prod"]
}

run "full_profile_switches_are_declared_and_default_safe" {
  command = plan

  assert {
    condition     = var.outbound_mode == "direct-nat" && var.transit_gateway_id == null
    error_message = "The root must default to the in-VPC NAT egress dev already uses."
  }

  assert {
    condition     = var.enable_full_profile_cluster_prerequisites == false && length(var.aws_load_balancer_controller_policy_arns) == 0
    error_message = "The root must not enable Karpenter or load-balancer prerequisites by default."
  }

  assert {
    condition     = var.create_canonical_hosted_zone == false
    error_message = "Canonical zone creation must default off in this root; owning microtodosuite.online is a separately approved change."
  }

  assert {
    condition     = length(var.canonical_destination_records) == 0
    error_message = "Destination records must default empty; routing traffic to the canonical domain is a separate named approval."
  }

  assert {
    condition     = var.enable_platform_image_mirror == false && length(var.github_platform_mirror_job_workflow_refs) == 0
    error_message = "The platform image mirror must default off in this root."
  }

  assert {
    condition     = length(var.additional_eks_oidc_issuers) == 0
    error_message = "No additional cluster issuer may be trusted by default."
  }
}

run "root_refuses_to_rename_the_legacy_zone_to_the_canonical_domain" {
  command = plan

  variables {
    public_hosted_zone_name = "microtodosuite.online"
  }

  expect_failures = [var.public_hosted_zone_name]
}
