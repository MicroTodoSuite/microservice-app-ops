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

override_resource {
  target          = aws_secretsmanager_secret.environment_jwt["dev"]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/dev/auth-api-secrets-test"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.environment_jwt["staging"]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/staging/auth-api-secrets-test"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.environment_jwt["prod"]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microtodosuite/prod/auth-api-secrets-test"
  }
}

run "managed_secret_contract" {
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
    condition     = length(aws_secretsmanager_secret.environment_jwt) == 3
    error_message = "Exactly three environment-local JWT source secrets must be managed."
  }

  assert {
    condition = toset([for secret in aws_secretsmanager_secret.environment_jwt : secret.name]) == toset([
      "microtodosuite/dev/auth-api-secrets",
      "microtodosuite/staging/auth-api-secrets",
      "microtodosuite/prod/auth-api-secrets",
    ])
    error_message = "JWT source secrets must use the three exact environment paths."
  }

  assert {
    condition     = alltrue([for secret in aws_secretsmanager_secret.environment_jwt : secret.recovery_window_in_days == 30])
    error_message = "JWT source secrets must retain the maximum recovery window."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.environment_jwt) == 3 && alltrue([for version in aws_secretsmanager_secret_version.environment_jwt : version.secret_string_wo_version == 1])
    error_message = "Each source secret must have one write-only version controlled by the rotation input."
  }

  assert {
    condition     = length(aws_iam_role.environment_jwt_reader) == 3
    error_message = "Exactly three environment JWT reader roles must exist."
  }

  assert {
    condition = alltrue([
      for environment, role in aws_iam_role.environment_jwt_reader :
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/test:sub"] == "system:serviceaccount:microtodo-${environment}:external-secrets-jwt"
    ])
    error_message = "Every reader role must trust only its exact namespace ServiceAccount subject."
  }

  assert {
    condition = alltrue([
      for environment, policy in aws_iam_role_policy.environment_jwt_reader :
      toset(jsondecode(policy.policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
      && jsondecode(policy.policy).Statement[0].Resource == aws_secretsmanager_secret.environment_jwt[environment].arn
    ])
    error_message = "JWT readers may only describe and read their exact source secret."
  }
}

# ---------------------------------------------------------------------------
# Full-profile secret containers and consumer readers (spec 009, T012/T019).
#
# Three containers are added by the owning foundation:
#   microtodosuite/observability/grafana-admin
#   microtodosuite/tooling/sonarqube-db
#   microtodosuite/tooling/sonarqube-admin
#
# Their values reach AWS only through `ephemeral "random_password"` into
# `secret_string_wo`, paired with a non-secret rotation counter. Terraform
# re-evaluates the ephemeral value during apply and never persists it, so a
# counter change is the only rotation trigger.
# ---------------------------------------------------------------------------

run "full_profile_secret_containers_are_off_by_default" {
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
    condition     = var.enable_full_profile_tooling_secrets == false
    error_message = "enable_full_profile_tooling_secrets must default off so the applied dev foundation is unchanged."
  }

  assert {
    condition     = length(aws_secretsmanager_secret.tooling) == 0 && length(aws_secretsmanager_secret_version.tooling) == 0
    error_message = "No full-profile secret container may exist while the switch is off."
  }

  assert {
    condition     = length(aws_iam_role.sonarqube_secrets_reader) == 0
    error_message = "No Sonar reader may exist while the tooling secrets are disabled."
  }

  assert {
    condition     = length(aws_secretsmanager_secret.environment_jwt) == 3
    error_message = "Dev must keep exactly its three environment JWT secrets."
  }
}

run "full_profile_secret_containers_are_write_only_and_versioned" {
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
  }

  assert {
    condition = jsonencode(sort([for secret in aws_secretsmanager_secret.tooling : secret.name])) == jsonencode([
      "microtodosuite/observability/grafana-admin",
      "microtodosuite/tooling/sonarqube-admin",
      "microtodosuite/tooling/sonarqube-db",
    ])
    error_message = "The owning foundation must create exactly the three reviewed full-profile secret containers."
  }

  # secret_string is state-persisted; secret_string_wo is not. Only the
  # write-only argument and its non-secret counter may ever be set.
  assert {
    condition = alltrue([
      for version in aws_secretsmanager_secret_version.tooling :
      version.secret_string == null && version.secret_string_wo_version == 1
    ])
    error_message = "Full-profile secret values must flow only through secret_string_wo with an explicit non-secret rotation counter."
  }

  assert {
    condition = alltrue([
      for secret in aws_secretsmanager_secret.tooling :
      secret.recovery_window_in_days == 30
    ])
    error_message = "A deleted full-profile secret must stay recoverable."
  }
}

run "reject_enabling_tooling_secrets_without_every_value_and_counter" {
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
      grafana_admin = "mock-grafana-admin-value"
    }
    full_profile_secret_versions = {
      grafana_admin = 1
    }
  }

  expect_failures = [var.full_profile_secret_values]
}

run "consumer_reads_one_environment_jwt_and_creates_no_secret" {
  command = plan

  variables {
    expected_account_id            = "123456789012"
    aws_region                     = "us-east-1"
    environment                    = "full-dev"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.60.0.0/16"
    public_subnet_cidrs            = ["10.60.0.0/24", "10.60.1.0/24", "10.60.2.0/24"]
    private_subnet_cidrs           = ["10.60.16.0/20", "10.60.32.0/20", "10.60.48.0/20"]
    cluster_public_access_cidrs    = ["203.0.113.10/32"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-admin"]
    create_shared_resources        = false
    shared_environments            = []
    environment_jwt_values         = {}
    consumer_jwt_environment       = "dev"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.environment_jwt) == 0 && length(aws_secretsmanager_secret_version.environment_jwt) == 0
    error_message = "A consumer foundation must create zero secret containers and zero secret versions."
  }

  assert {
    condition     = length(data.aws_secretsmanager_secret.consumer_jwt) == 1
    error_message = "A consumer must look up the owner's JWT secret instead of creating its own."
  }

  # Cluster-qualified: two consumer clusters reading the same environment must
  # not collide on one role name, and each must trust only its own issuer.
  assert {
    condition     = aws_iam_role.consumer_jwt_reader[0].name == "microtodosuite-full-dev-dev-jwt-reader"
    error_message = "The consumer JWT reader must be qualified by its own cluster."
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role.consumer_jwt_reader[0].assume_role_policy).Statement[0].Condition.StringEquals) == jsonencode({
      "oidc.eks.us-east-1.amazonaws.com/id/test:aud" = "sts.amazonaws.com"
      "oidc.eks.us-east-1.amazonaws.com/id/test:sub" = "system:serviceaccount:microtodo-dev:external-secrets-jwt"
    })
    error_message = "The consumer JWT reader must trust only its own cluster issuer and only its one environment's ServiceAccount."
  }

  assert {
    condition     = length(aws_iam_role.environment_jwt_reader) == 0
    error_message = "A consumer must not create the owner's per-environment reader roles."
  }
}

run "reject_consumer_jwt_reader_on_the_owning_foundation" {
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
    consumer_jwt_environment       = "dev"
  }

  expect_failures = [var.consumer_jwt_environment]
}
