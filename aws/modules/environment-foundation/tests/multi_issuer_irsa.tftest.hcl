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


# ---------------------------------------------------------------------------
# Multi-issuer shared IRSA trust (spec 009, T012/T019).
#
# The shared reader roles are singletons owned by one foundation, but the full
# profile runs several clusters, each with its own OIDC issuer. Those clusters
# must be able to assume the same shared roles without a second copy being
# created, and without the trust widening to anything but an exact
# issuer/audience/subject triple.
#
# With no additional issuer configured the rendered trust policy must be
# byte-identical to today's, so the applied dev foundation does not change.
# ---------------------------------------------------------------------------

override_resource {
  target          = aws_iam_openid_connect_provider.github_actions[0]
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

run "single_issuer_trust_is_unchanged_by_default" {
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
    condition     = length(var.additional_eks_oidc_issuers) == 0
    error_message = "additional_eks_oidc_issuers must default empty so no existing trust widens."
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy)) == jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "AllowExactObservabilityExternalSecretsServiceAccount"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/test"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.eks.us-east-1.amazonaws.com/id/test:aud" = "sts.amazonaws.com"
            "oidc.eks.us-east-1.amazonaws.com/id/test:sub" = "system:serviceaccount:observability:observability-external-secrets-jwt"
          }
        }
      }]
    })
    error_message = "With no additional issuer the observability trust must stay exactly the single-issuer policy it is today."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.security_secrets_reader[0].assume_role_policy).Statement) == 1 &&
      length(jsondecode(aws_iam_role.kyverno_ecr_verifier[0].assume_role_policy).Statement) == 1
    )
    error_message = "The security and Kyverno roles must keep exactly one trust statement by default."
  }
}

run "additional_issuers_extend_only_the_shared_reader_trust" {
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
    additional_eks_oidc_issuers = {
      "eks-prod-full" = {
        provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/PRODFULL"
        issuer_host  = "oidc.eks.us-east-1.amazonaws.com/id/PRODFULL"
      }
    }
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy).Statement) == 2
    error_message = "A second reviewed cluster must be able to assume the shared observability reader."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy).Statement :
      statement.Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/PRODFULL" &&
      statement.Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/PRODFULL:sub"] == "system:serviceaccount:observability:observability-external-secrets-jwt"
    ])
    error_message = "The added issuer must be bound to the exact same service-account subject, not a wildcard."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy).Statement :
      statement.Action == "sts:AssumeRoleWithWebIdentity" && statement.Effect == "Allow"
    ])
    error_message = "Every shared-reader trust statement must remain a web-identity allow."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role.observability_secrets_reader[0].assume_role_policy).Statement :
      anytrue([for key, value in statement.Condition.StringEquals : endswith(key, ":aud") && value == "sts.amazonaws.com"])
    ])
    error_message = "Every shared-reader trust statement must pin the sts.amazonaws.com audience."
  }

  # The GitHub publisher is not an EKS principal and must never gain one.
  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role.github_ecr_publisher[0].assume_role_policy).Statement :
      statement.Principal.Federated == local.github_actions_oidc_provider_arn
    ])
    error_message = "The GitHub publisher must never be extended with EKS trust."
  }
}

run "reject_additional_issuer_with_mismatched_host" {
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
    additional_eks_oidc_issuers = {
      "eks-prod-full" = {
        provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/PRODFULL"
        issuer_host  = "oidc.eks.us-east-1.amazonaws.com/id/SOMETHINGELSE"
      }
    }
  }

  expect_failures = [var.additional_eks_oidc_issuers]
}

run "reject_additional_issuer_that_is_not_an_eks_issuer" {
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
    additional_eks_oidc_issuers = {
      "github" = {
        provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        issuer_host  = "token.actions.githubusercontent.com"
      }
    }
  }

  expect_failures = [var.additional_eks_oidc_issuers]
}
