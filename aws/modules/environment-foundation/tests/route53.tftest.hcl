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

override_resource {
  target          = aws_route53_zone.public[0]
  override_during = plan
  values = {
    zone_id = "Z0123456789ABCDEF"
    name_servers = [
      "ns-100.awsdns-10.com",
      "ns-200.awsdns-20.net",
      "ns-300.awsdns-30.org",
      "ns-400.awsdns-40.co.uk",
    ]
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

run "public_hosted_zone_contract" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.abrdns.com"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition     = length(aws_route53_zone.public) == 1 && aws_route53_zone.public[0].name == "microtodosuite.abrdns.com"
    error_message = "The foundation must manage exactly the registered microtodosuite.abrdns.com public hosted zone."
  }

  assert {
    condition     = !aws_route53_zone.public[0].force_destroy && aws_route53_zone.public[0].tags.ManagedBy == "Terraform"
    error_message = "The public zone must refuse forced record cleanup and retain Terraform ownership tags."
  }

  assert {
    condition     = output.public_hosted_zone_name == "microtodosuite.abrdns.com" && output.public_hosted_zone_id == "Z0123456789ABCDEF"
    error_message = "The module must expose the public hosted-zone identity."
  }

  assert {
    condition     = length(output.public_hosted_zone_name_servers) == 4
    error_message = "The module must expose all four authoritative name servers assigned by Route 53."
  }
}

run "public_hosted_zone_is_opt_in" {
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
  }

  assert {
    condition     = length(aws_route53_zone.public) == 0 && output.public_hosted_zone_name == null && length(output.public_hosted_zone_name_servers) == 0
    error_message = "Reusable foundation instances must not create duplicate public zones unless explicitly configured."
  }
}
