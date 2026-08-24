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

run "ecr_and_irsa_contract" {
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
    condition     = length(aws_ecr_repository.services) == 5
    error_message = "Exactly five legacy environment-qualified repositories must remain managed."
  }

  assert {
    condition = toset([for repository in aws_ecr_repository.services : repository.name]) == toset([
      "microtodosuite/dev/auth-api",
      "microtodosuite/dev/frontend",
      "microtodosuite/dev/log-message-processor",
      "microtodosuite/dev/todos-api",
      "microtodosuite/dev/users-api",
    ])
    error_message = "The five legacy repositories must retain their existing names."
  }

  assert {
    condition     = length(aws_ecr_repository.neutral_services) == 5
    error_message = "Exactly five additive environment-neutral repositories must be created."
  }

  assert {
    condition = toset([for repository in aws_ecr_repository.neutral_services : repository.name]) == toset([
      "microtodosuite/auth-api",
      "microtodosuite/frontend",
      "microtodosuite/log-message-processor",
      "microtodosuite/todos-api",
      "microtodosuite/users-api",
    ])
    error_message = "The neutral repositories must use the exact build-once names."
  }

  assert {
    condition     = alltrue([for repository in aws_ecr_repository.services : repository.image_tag_mutability == "IMMUTABLE" && repository.encryption_configuration[0].encryption_type == "AES256" && repository.image_scanning_configuration[0].scan_on_push])
    error_message = "Every ECR repository must be immutable, encrypted, and scan on push."
  }

  assert {
    condition     = alltrue([for repository in aws_ecr_repository.neutral_services : repository.image_tag_mutability == "IMMUTABLE" && repository.encryption_configuration[0].encryption_type == "AES256" && repository.image_scanning_configuration[0].scan_on_push && repository.tags.Environment == "shared"])
    error_message = "Every neutral repository must be immutable, encrypted, scanned, and tagged as shared."
  }

  assert {
    condition     = alltrue([for policy in aws_ecr_lifecycle_policy.services : jsondecode(policy.policy).rules[0].selection.tagStatus == "untagged"])
    error_message = "ECR lifecycle policies may expire only untagged images."
  }

  assert {
    condition     = alltrue([for policy in aws_ecr_lifecycle_policy.neutral_services : jsondecode(policy.policy).rules[0].selection.tagStatus == "untagged"])
    error_message = "Neutral ECR lifecycle policies may expire only untagged images."
  }

  assert {
    condition     = jsondecode(aws_iam_role.vpc_cni.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/test:sub"] == "system:serviceaccount:kube-system:aws-node"
    error_message = "The CNI role trust must bind only kube-system/aws-node."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.vpc_cni.policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    error_message = "AmazonEKS_CNI_Policy must be attached to the exact CNI role."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.node)) == toset(["ecr_pull", "worker"])
    error_message = "The node role must contain only worker and ECR pull managed policies."
  }
}
