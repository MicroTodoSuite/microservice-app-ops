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

# ---------------------------------------------------------------------------
# Canonical domain contract (spec 009, T019).
#
# microtodosuite.online is introduced at its own Terraform address, default
# off. It must never be expressed by renaming public_hosted_zone_name: the name
# forces replacement, so a rename would destroy the legacy zone, drop every
# record in it, and invalidate the delegation configured at the registrar.
# ---------------------------------------------------------------------------

run "canonical_zone_is_off_by_default_and_leaves_the_legacy_zone_alone" {
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
    condition     = var.create_canonical_hosted_zone == false
    error_message = "create_canonical_hosted_zone must default off; the canonical domain is a separately approved change."
  }

  assert {
    condition     = length(aws_route53_zone.canonical) == 0
    error_message = "No canonical hosted zone may exist until it is explicitly enabled."
  }

  assert {
    condition     = length(aws_route53_zone.public) == 1 && aws_route53_zone.public[0].name == "microtodosuite.abrdns.com"
    error_message = "Introducing the canonical zone must leave the legacy zone untouched at its own address."
  }

  assert {
    condition     = output.canonical_hosted_zone_name == null && output.canonical_hosted_zone_id == null
    error_message = "The canonical zone identity must be null while the zone is disabled."
  }
}

run "canonical_zone_is_a_separate_address_from_the_legacy_zone" {
  command = plan

  # Route 53 assigns the zone id and name servers at create time, so the plan
  # cannot know them. Mock them exactly as the legacy zone is mocked above.
  override_resource {
    target          = aws_route53_zone.canonical[0]
    override_during = plan
    values = {
      zone_id = "Z0FEDCBA9876543"
      name_servers = [
        "ns-101.awsdns-11.com",
        "ns-201.awsdns-21.net",
        "ns-301.awsdns-31.org",
        "ns-401.awsdns-41.co.uk",
      ]
    }
  }

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.abrdns.com"
    create_canonical_hosted_zone   = true
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition     = length(aws_route53_zone.canonical) == 1 && aws_route53_zone.canonical[0].name == "microtodosuite.online"
    error_message = "Enabling the canonical zone must create exactly microtodosuite.online."
  }

  assert {
    condition     = length(aws_route53_zone.public) == 1 && aws_route53_zone.public[0].name == "microtodosuite.abrdns.com"
    error_message = "The legacy zone must survive unchanged at its own address when the canonical zone is enabled."
  }

  assert {
    condition     = !aws_route53_zone.canonical[0].force_destroy
    error_message = "The canonical zone must refuse forced record cleanup."
  }

  assert {
    condition     = output.canonical_hosted_zone_name == "microtodosuite.online"
    error_message = "The module must expose the canonical hosted-zone identity once it exists."
  }

  assert {
    condition     = length(output.canonical_hosted_zone_name_servers) == 4
    error_message = "The module must expose all four canonical name servers to configure at the registrar."
  }
}

run "canonical_zone_does_not_create_application_records_by_default" {
  command = plan

  # Route 53 assigns the zone id and name servers at create time, so the plan
  # cannot know them. Mock them exactly as the legacy zone is mocked above.
  override_resource {
    target          = aws_route53_zone.canonical[0]
    override_during = plan
    values = {
      zone_id = "Z0FEDCBA9876543"
      name_servers = [
        "ns-101.awsdns-11.com",
        "ns-201.awsdns-21.net",
        "ns-301.awsdns-31.org",
        "ns-401.awsdns-41.co.uk",
      ]
    }
  }

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.abrdns.com"
    create_canonical_hosted_zone   = true
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition     = length(var.canonical_destination_records) == 0
    error_message = "canonical_destination_records must default empty; enabling application traffic is a separate named approval."
  }

  assert {
    condition     = length(aws_route53_record.canonical_destination) == 0
    error_message = "No application record may exist until a traffic owner supplies a reviewed destination."
  }
}

run "reject_canonical_records_without_the_canonical_zone" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.abrdns.com"
    create_canonical_hosted_zone   = false
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    canonical_destination_records = {
      app = {
        dns_name = "example-alb-123.us-east-1.elb.amazonaws.com"
        zone_id  = "Z35SXDOTRQ7X7K"
      }
    }
  }

  expect_failures = [var.canonical_destination_records]
}

run "reject_renaming_the_legacy_zone_to_the_canonical_domain" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    public_hosted_zone_name        = "microtodosuite.online"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  expect_failures = [var.public_hosted_zone_name]
}
