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

run "dev_root_inventory" {
  command = plan

  variables {
    environment                    = "dev"
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.abrdns.com"
    shared_environments            = ["dev", "staging", "prod"]
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition     = output.environment == "dev"
    error_message = "The root must expose only the dev environment."
  }

  assert {
    condition     = output.foundation_contract.environment == "dev" && output.foundation_contract.ecr_service_count == 5 && output.foundation_contract.identity_mode == "IRSA"
    error_message = "The root inventory must remain the dev-only VPC/EKS/ECR/IRSA scope."
  }

  assert {
    condition     = output.public_hosted_zone_name == "microtodosuite.abrdns.com" && output.public_hosted_zone_id == "Z0123456789ABCDEF" && length(output.public_hosted_zone_name_servers) == 4
    error_message = "The dev root must expose the hosted zone and exactly four authoritative name servers."
  }
}
