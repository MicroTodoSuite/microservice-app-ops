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

override_resource {
  target          = aws_iam_openid_connect_provider.github_actions
  override_during = plan
  values = {
    arn = "arn:aws:iam::995253610162:oidc-provider/token.actions.githubusercontent.com"
  }
}

variables {
  environment_jwt_values = {
    dev     = "mock-dev-jwt-value"
    staging = "mock-staging-jwt-value"
    prod    = "mock-prod-jwt-value"
  }
}

run "github_oidc_contract" {
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
    condition     = aws_iam_openid_connect_provider.github_actions.url == "https://token.actions.githubusercontent.com" && aws_iam_openid_connect_provider.github_actions.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The GitHub provider must use the exact issuer and STS audience."
  }

  assert {
    condition     = aws_iam_role.github_ecr_publisher.name == "microtodosuite-github-ecr-publisher"
    error_message = "The publisher role must have the exact workflow-owned name."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role.github_ecr_publisher.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset([
      "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
    ])
    error_message = "The publisher trust must contain only the five exact reviewed-main subjects."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.github_ecr_publisher.policy).Statement[0].Action == "ecr:GetAuthorizationToken" && jsondecode(aws_iam_role_policy.github_ecr_publisher.policy).Statement[0].Resource == "*"
    error_message = "Only the ECR authorization call may use a wildcard resource."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.github_ecr_publisher.policy).Statement[1].Resource) == toset([for service in var.neutral_service_names : "arn:aws:ecr:us-east-1:995253610162:repository/microtodosuite/${service}"])
    error_message = "Publisher ECR permissions must be limited to the five neutral repositories."
  }
}
