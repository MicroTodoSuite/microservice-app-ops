mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "995253610162"
      arn        = "arn:aws:iam::995253610162:role/test"
      id         = "995253610162"
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
    vpc_flow_log_destination_arn = "arn:aws:logs:us-east-1:995253610162:log-group:/aws/vpc-flow-logs/microtodosuite-dev"
  }
}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "microtodosuite-dev"
    cluster_arn                        = "arn:aws:eks:us-east-1:995253610162:cluster/microtodosuite-dev"
    cluster_endpoint                   = "https://example.eks.amazonaws.com"
    cluster_certificate_authority_data = "dGVzdA=="
    cluster_service_cidr               = "172.20.0.0/16"
    cluster_primary_security_group_id  = "sg-primary"
    node_security_group_id             = "sg-node"
    cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/test"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/test"
    oidc_provider_arn                  = "arn:aws:iam::995253610162:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/test"
  }
}

override_module {
  target = module.bootstrap_node_group
  outputs = {
    node_group_id     = "microtodosuite-dev:bootstrap"
    node_group_arn    = "arn:aws:eks:us-east-1:995253610162:nodegroup/microtodosuite-dev/bootstrap/test"
    node_group_status = "ACTIVE"
  }
}

variables {
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
    arn = "arn:aws:secretsmanager:us-east-1:995253610162:secret:microtodosuite/dev/auth-api-secrets-test"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.environment_jwt["staging"]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:995253610162:secret:microtodosuite/staging/auth-api-secrets-test"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.environment_jwt["prod"]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:995253610162:secret:microtodosuite/prod/auth-api-secrets-test"
  }
}

run "managed_secret_contract" {
  command = plan

  variables {
    expected_account_id            = "995253610162"
    aws_region                     = "us-east-1"
    availability_zones             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    vpc_cidr                       = "10.10.0.0/16"
    public_subnet_cidrs            = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    private_subnet_cidrs           = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]
    cluster_public_access_cidrs    = ["0.0.0.0/0"]
    bootstrap_admin_principal_arns = ["arn:aws:iam::995253610162:role/platform-admin"]
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
