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
  environment         = "dev"
  shared_environments = ["dev", "staging", "prod"]
  environment_jwt_values = {
    dev     = "mock-dev-jwt-value"
    staging = "mock-staging-jwt-value"
    prod    = "mock-prod-jwt-value"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.observability_slack_webhook[0]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:995253610162:secret:microtodosuite/observability/alertmanager-slack-webhook-test"
  }
}

override_resource {
  target          = aws_secretsmanager_secret.security_slack_webhook[0]
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:us-east-1:995253610162:secret:microtodosuite/security/falcosidekick-slack-webhook-test"
  }
}

run "observability_security_secrets_reader_contract" {
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
    condition     = aws_secretsmanager_secret.observability_slack_webhook[0].name == "microtodosuite/observability/alertmanager-slack-webhook"
    error_message = "The Alertmanager Slack webhook must use the exact observability secret path."
  }

  assert {
    condition     = aws_secretsmanager_secret.observability_slack_webhook[0].recovery_window_in_days == 30
    error_message = "The Alertmanager Slack webhook secret must retain the maximum recovery window."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.environment_jwt) == 3
    error_message = "This feature must not touch the unrelated environment JWT secret versions."
  }

  assert {
    condition     = aws_iam_role.observability_secrets_reader[0].name == "microtodosuite-observability-secrets-reader"
    error_message = "Observability must use the exact secrets-reader role name."
  }

  assert {
    condition     = jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/test:sub"] == "system:serviceaccount:observability:observability-external-secrets-jwt"
    error_message = "The observability reader role must trust only the observability namespace's External Secrets ServiceAccount."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.observability_secrets_reader[0].policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
    error_message = "The observability reader may only describe and read the secret."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.observability_secrets_reader[0].policy).Statement[0].Resource == aws_secretsmanager_secret.observability_slack_webhook[0].arn
    error_message = "The observability reader must be scoped to exactly its own secret, not a wildcard."
  }

  assert {
    condition     = aws_secretsmanager_secret.security_slack_webhook[0].name == "microtodosuite/security/falcosidekick-slack-webhook"
    error_message = "The Falcosidekick Slack webhook must use the exact security secret path."
  }

  assert {
    condition     = aws_secretsmanager_secret.security_slack_webhook[0].recovery_window_in_days == 30
    error_message = "The Falcosidekick Slack webhook secret must retain the maximum recovery window."
  }

  assert {
    condition     = aws_iam_role.security_secrets_reader[0].name == "microtodosuite-security-secrets-reader"
    error_message = "Security must use the exact secrets-reader role name."
  }

  assert {
    condition     = jsondecode(aws_iam_role.security_secrets_reader[0].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/test:sub"] == "system:serviceaccount:security:security-external-secrets-jwt"
    error_message = "The security reader role must trust only the security namespace's External Secrets ServiceAccount."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.security_secrets_reader[0].policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
    error_message = "The security reader may only describe and read the secret."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.security_secrets_reader[0].policy).Statement[0].Resource == aws_secretsmanager_secret.security_slack_webhook[0].arn
    error_message = "The security reader must be scoped to exactly its own secret, not a wildcard."
  }

  assert {
    condition     = aws_iam_role.observability_secrets_reader[0].name != aws_iam_role.security_secrets_reader[0].name
    error_message = "Observability and security must never share a reader role."
  }
}
