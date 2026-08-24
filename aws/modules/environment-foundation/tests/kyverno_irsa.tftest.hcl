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

run "kyverno_verifier_contract" {
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
    condition     = aws_iam_role.kyverno_ecr_verifier.name == "microtodosuite-kyverno-ecr-verifier"
    error_message = "Kyverno must use the exact verifier role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.kyverno_ecr_verifier.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/test:sub"] == "system:serviceaccount:kyverno:kyverno-admission-controller"
    error_message = "Kyverno verifier trust must bind only the admission-controller ServiceAccount."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.kyverno_ecr_verifier.policy).Statement[0].Action == "ecr:GetAuthorizationToken" && jsondecode(aws_iam_role_policy.kyverno_ecr_verifier.policy).Statement[0].Resource == "*"
    error_message = "Only the read-only ECR authorization call may use a wildcard resource."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.kyverno_ecr_verifier.policy).Statement[1].Action) == toset(["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"])
    error_message = "Kyverno verifier permissions must remain read-only."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.kyverno_ecr_verifier.policy).Statement[1].Resource) == toset([for service in var.neutral_service_names : "arn:aws:ecr:us-east-1:123456789012:repository/microtodosuite/${service}"])
    error_message = "Kyverno verifier permissions must be limited to the five neutral repositories."
  }
}
