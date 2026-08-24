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

  mock_data "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/microtodosuite/mock"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/mock"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_data "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-shared-role"
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      arn  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/mock-shared-secret"
      name = "microtodosuite/mock-shared-secret"
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

run "github_oidc_contract" {
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
    condition     = aws_iam_openid_connect_provider.github_actions[0].url == "https://token.actions.githubusercontent.com" && aws_iam_openid_connect_provider.github_actions[0].client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The GitHub provider must use the exact issuer and STS audience."
  }

  assert {
    condition     = aws_iam_role.github_ecr_publisher[0].name == "microtodosuite-github-ecr-publisher"
    error_message = "The publisher role must have the exact workflow-owned name."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role.github_ecr_publisher[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset([
      "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
    ])
    error_message = "The publisher trust must contain only the five exact reviewed-main subjects."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.github_ecr_publisher[0].policy).Statement[0].Action == "ecr:GetAuthorizationToken" && jsondecode(aws_iam_role_policy.github_ecr_publisher[0].policy).Statement[0].Resource == "*"
    error_message = "Only the ECR authorization call may use a wildcard resource."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.github_ecr_publisher[0].policy).Statement[1].Resource) == toset([for service in var.neutral_service_names : "arn:aws:ecr:us-east-1:123456789012:repository/microtodosuite/${service}"])
    error_message = "Publisher ECR permissions must be limited to the five neutral repositories."
  }
}

run "shared_resource_consumer_contract" {
  command = plan

  variables {
    create_shared_resources        = false
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.20.0.0/16"
    public_subnet_cidrs            = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    private_subnet_cidrs           = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
    cluster_public_access_cidrs    = ["192.0.2.1/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
  }

  assert {
    condition = (
      length(aws_ecr_repository.neutral_services) == 0 &&
      length(aws_ecr_lifecycle_policy.neutral_services) == 0 &&
      length(aws_iam_openid_connect_provider.github_actions) == 0 &&
      length(aws_iam_role.github_ecr_publisher) == 0 &&
      length(aws_iam_role_policy.github_ecr_publisher) == 0 &&
      length(aws_iam_role.kyverno_ecr_verifier) == 0 &&
      length(aws_iam_role_policy.kyverno_ecr_verifier) == 0 &&
      length(aws_secretsmanager_secret.observability_slack_webhook) == 0 &&
      length(aws_iam_role.observability_secrets_reader) == 0 &&
      length(aws_iam_role_policy.observability_secrets_reader) == 0 &&
      length(aws_secretsmanager_secret.security_slack_webhook) == 0 &&
      length(aws_iam_role.security_secrets_reader) == 0 &&
      length(aws_iam_role_policy.security_secrets_reader) == 0
    )
    error_message = "Consumer mode must not manage any account-level shared resources."
  }

  assert {
    condition = (
      length(data.aws_ecr_repository.neutral_services) == 5 &&
      length(data.aws_iam_openid_connect_provider.github_actions) == 1 &&
      length(data.aws_iam_role.github_ecr_publisher) == 1 &&
      length(data.aws_iam_role.kyverno_ecr_verifier) == 1 &&
      length(data.aws_secretsmanager_secret.observability_slack_webhook) == 1 &&
      length(data.aws_iam_role.observability_secrets_reader) == 1 &&
      length(data.aws_secretsmanager_secret.security_slack_webhook) == 1 &&
      length(data.aws_iam_role.security_secrets_reader) == 1
    )
    error_message = "Consumer mode must look up every account-level shared resource."
  }
}

# ---------------------------------------------------------------------------
# Azure DR secret seed role (spec 009, T012/T019).
#
# One workflow copies exactly four AWS secrets into Azure Key Vault so a token
# minted on AWS stays valid after a request moves to Azure. It is the only
# identity in this account allowed to READ secret values, so its trust and its
# resource list are both pinned exactly.
# ---------------------------------------------------------------------------

run "dr_secret_seed_is_off_by_default" {
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
    condition     = var.enable_dr_secret_seed == false
    error_message = "enable_dr_secret_seed must default off; nothing may read secret values until DR is approved."
  }

  assert {
    condition     = length(aws_iam_role.dr_secret_seed) == 0 && length(aws_iam_role_policy.dr_secret_seed) == 0
    error_message = "No DR seed identity may exist while the switch is off."
  }
}

run "dr_secret_seed_reads_exactly_four_secrets_from_one_workflow" {
  command = plan

  variables {
    expected_account_id                 = "123456789012"
    aws_region                          = "us-east-1"
    availability_zones                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                            = "10.10.0.0/16"
    public_subnet_cidrs                 = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs                = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs         = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns      = ["arn:aws:iam::123456789012:role/platform-admin"]
    create_shared_resources             = true
    enable_full_profile_tooling_secrets = true
    full_profile_secret_values = {
      grafana_admin   = "mock-grafana-admin-value"
      sonarqube_db    = "mock-sonarqube-db-value"
      sonarqube_admin = "mock-sonarqube-admin-value"
    }
    full_profile_secret_versions = {
      grafana_admin   = 1
      sonarqube_db    = 1
      sonarqube_admin = 1
    }
    enable_dr_secret_seed        = true
    dr_secret_seed_subjects      = ["repo:MicroTodoSuite/.github:environment:azure-dr"]
    dr_secret_seed_workflow_refs = ["MicroTodoSuite/.github/.github/workflows/sync-dr-secrets.yml@refs/heads/main"]
  }

  assert {
    condition     = aws_iam_role.dr_secret_seed[0].name == "microtodosuite-github-dr-secret-seed"
    error_message = "The DR seed must use its own dedicated role."
  }

  # Repository AND environment AND the exact workflow file. Any one of the three
  # alone would let an unrelated job in the same repository read these values.
  assert {
    condition = jsonencode(jsondecode(aws_iam_role.dr_secret_seed[0].assume_role_policy).Statement[0].Condition.StringEquals) == jsonencode({
      "token.actions.githubusercontent.com:aud"              = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub"              = ["repo:MicroTodoSuite/.github:environment:azure-dr"]
      "token.actions.githubusercontent.com:job_workflow_ref" = ["MicroTodoSuite/.github/.github/workflows/sync-dr-secrets.yml@refs/heads/main"]
    })
    error_message = "The DR seed must be pinned to an exact repository, environment and workflow file."
  }

  assert {
    condition = jsonencode(sort(jsondecode(aws_iam_role_policy.dr_secret_seed[0].policy).Statement[0].Resource)) == jsonencode([
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/observability/alertmanager-slack-webhook",
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/observability/grafana-admin",
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/prod/auth-api-secrets",
      "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/security/falcosidekick-slack-webhook",
    ])
    error_message = "The DR seed must read exactly the four approved source ARNs."
  }

  assert {
    condition = jsonencode(sort(tolist(jsondecode(aws_iam_role_policy.dr_secret_seed[0].policy).Statement[0].Action))) == jsonencode([
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ])
    error_message = "The DR seed must only describe and read; it must never write or delete a secret."
  }

  # The publisher stays an artifact identity and never gains secret-read trust.
  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.github_ecr_publisher[0].policy).Statement :
      !can(regex("secretsmanager", jsonencode(statement.Action)))
    ])
    error_message = "The GitHub publisher must never gain secret-read permissions."
  }
}

run "reject_dr_secret_seed_without_its_exact_identity" {
  command = plan

  variables {
    expected_account_id                 = "123456789012"
    aws_region                          = "us-east-1"
    availability_zones                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                            = "10.10.0.0/16"
    public_subnet_cidrs                 = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs                = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs         = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns      = ["arn:aws:iam::123456789012:role/platform-admin"]
    create_shared_resources             = true
    enable_full_profile_tooling_secrets = true
    full_profile_secret_values = {
      grafana_admin   = "mock-grafana-admin-value"
      sonarqube_db    = "mock-sonarqube-db-value"
      sonarqube_admin = "mock-sonarqube-admin-value"
    }
    full_profile_secret_versions = {
      grafana_admin   = 1
      sonarqube_db    = 1
      sonarqube_admin = 1
    }
    enable_dr_secret_seed        = true
    dr_secret_seed_subjects      = []
    dr_secret_seed_workflow_refs = []
  }

  expect_failures = [
    var.dr_secret_seed_subjects,
    var.dr_secret_seed_workflow_refs,
  ]
}
