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

override_resource {
  target          = aws_iam_openid_connect_provider.github_actions[0]
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
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


# ---------------------------------------------------------------------------
# Platform image mirror contract (spec 009, T012/T019).
#
# The full profile runs third-party platform images (controllers, exporters,
# dashboards). They are mirrored into ONE dev-owned repository so the clusters
# never pull from an upstream registry at runtime. The mirror is default-off so
# the applied dev foundation keeps exactly the repositories it has today.
# ---------------------------------------------------------------------------

run "platform_mirror_is_off_by_default" {
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
    create_shared_resources        = true
  }

  assert {
    condition     = var.enable_platform_image_mirror == false
    error_message = "enable_platform_image_mirror must default off so the applied dev foundation is unchanged."
  }

  assert {
    condition     = length(aws_ecr_repository.platform_mirror) == 0 && length(aws_iam_role.github_platform_mirror) == 0
    error_message = "No mirror repository or mirror role may exist while the mirror is disabled."
  }

  assert {
    condition     = length(aws_ecr_repository.services) == 5 && length(aws_ecr_repository.neutral_services) == 5
    error_message = "Dev must keep exactly its five environment and five neutral service repositories."
  }

  assert {
    condition     = output.foundation_contract.ecr_service_count == 5
    error_message = "The mirror must not be counted as a business service repository."
  }
}

run "platform_mirror_is_one_hardened_dev_owned_repository" {
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
    create_shared_resources        = true
    enable_platform_image_mirror   = true
    github_platform_mirror_job_workflow_refs = [
      "MicroTodoSuite/.github/.github/workflows/mirror-platform-images.yml@refs/heads/main",
    ]
  }

  assert {
    condition     = length(aws_ecr_repository.platform_mirror) == 1
    error_message = "Exactly one platform mirror repository must exist."
  }

  assert {
    condition     = aws_ecr_repository.platform_mirror[0].name == "microtodosuite/platform"
    error_message = "The mirror must be the single microtodosuite/platform repository."
  }

  assert {
    condition = (
      aws_ecr_repository.platform_mirror[0].image_tag_mutability == "IMMUTABLE" &&
      aws_ecr_repository.platform_mirror[0].force_delete == false
    )
    error_message = "The mirror must be immutable and refuse forced deletion; a mirrored digest is what every cluster resolves."
  }

  assert {
    condition = (
      one(aws_ecr_repository.platform_mirror[0].encryption_configuration).encryption_type == "AES256" &&
      one(aws_ecr_repository.platform_mirror[0].image_scanning_configuration).scan_on_push == true
    )
    error_message = "The mirror must be encrypted and scanned on push, like every other repository in this account."
  }

  assert {
    condition     = length(aws_ecr_repository.services) == 5 && length(aws_ecr_repository.neutral_services) == 5
    error_message = "Adding the mirror must not disturb the ten existing service repositories."
  }

  assert {
    condition     = local.platform_mirror_repository_arn == "arn:aws:ecr:us-east-1:123456789012:repository/microtodosuite/platform"
    error_message = "The module must resolve the mirror to exactly one repository ARN for the GitOps image graph."
  }
}

run "platform_mirror_role_is_separate_and_scoped_to_one_repository" {
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
    create_shared_resources        = true
    enable_platform_image_mirror   = true
    github_platform_mirror_job_workflow_refs = [
      "MicroTodoSuite/.github/.github/workflows/mirror-platform-images.yml@refs/heads/main",
    ]
  }

  assert {
    condition     = aws_iam_role.github_platform_mirror[0].name == "microtodosuite-github-platform-mirror"
    error_message = "The mirror must use its own role, distinct from the service publisher."
  }

  assert {
    condition     = aws_iam_role.github_platform_mirror[0].name != local.github_ecr_publisher_role_name
    error_message = "The mirror role and the service publisher role must never be the same principal."
  }

  # The publisher's blast radius must not grow. It keeps exactly its five
  # neutral repositories and never gains mirror, EKS, or secret-read trust.
  assert {
    condition     = jsonencode(jsondecode(aws_iam_role_policy.github_ecr_publisher[0].policy).Statement[1].Resource) == jsonencode(local.neutral_ecr_repository_arns)
    error_message = "The GitHub publisher must stay scoped to exactly the five neutral service repositories."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.github_platform_mirror[0].policy).Statement :
      statement.Sid == "AuthenticateToEcr" || jsonencode(statement.Resource) == jsonencode([
        "arn:aws:ecr:us-east-1:123456789012:repository/microtodosuite/platform"
      ])
    ])
    error_message = "The mirror role must reach exactly one repository: microtodosuite/platform."
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role.github_platform_mirror[0].assume_role_policy).Statement[0].Condition.StringEquals) == jsonencode({
      "token.actions.githubusercontent.com:aud"              = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:job_workflow_ref" = ["MicroTodoSuite/.github/.github/workflows/mirror-platform-images.yml@refs/heads/main"]
    })
    error_message = "The mirror role must trust an exact reviewed workflow, not a repository or a branch."
  }
}

run "reject_platform_mirror_without_an_exact_workflow" {
  command = plan

  variables {
    expected_account_id                      = "123456789012"
    aws_region                               = "us-east-1"
    availability_zones                       = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                                 = "10.10.0.0/16"
    public_subnet_cidrs                      = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs                     = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs              = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns           = ["arn:aws:iam::123456789012:role/platform-admin"]
    create_shared_resources                  = true
    enable_platform_image_mirror             = true
    github_platform_mirror_job_workflow_refs = []
  }

  expect_failures = [var.github_platform_mirror_job_workflow_refs]
}

run "consumer_reads_the_mirror_it_does_not_own" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    environment                    = "demo-full"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.40.0.0/16"
    public_subnet_cidrs            = ["10.40.0.0/24", "10.40.1.0/24", "10.40.2.0/24"]
    private_subnet_cidrs           = ["10.40.16.0/20", "10.40.32.0/20", "10.40.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    create_shared_resources        = false
    shared_environments            = []
    environment_jwt_values         = {}
    enable_platform_image_mirror   = true
  }

  assert {
    condition     = length(aws_ecr_repository.platform_mirror) == 0 && length(aws_iam_role.github_platform_mirror) == 0
    error_message = "A consumer foundation must never create a second copy of the singleton mirror or its role."
  }

  assert {
    condition     = length(data.aws_ecr_repository.platform_mirror) == 1
    error_message = "A consumer foundation must read the dev-owned mirror instead of creating one."
  }
}
