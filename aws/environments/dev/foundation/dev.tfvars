environment = "dev"
# Human-approved, non-secret dev foundation configuration shared by the team.
expected_account_id     = "916491575487"
aws_region              = "us-east-1"
public_hosted_zone_name = "microtodosuite.abrdns.com"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c",
]

# 10.10.0.0/16 is reserved for dev. Future staging and production specs must
# use non-overlapping 10.20.0.0/16 and 10.30.0.0/16 ranges, respectively.
vpc_cidr = "10.10.0.0/16"

public_subnet_cidrs = [
  "10.10.0.0/24",
  "10.10.1.0/24",
  "10.10.2.0/24",
]

private_subnet_cidrs = [
  "10.10.16.0/20",
  "10.10.32.0/20",
  "10.10.48.0/20",
]

# Dev retains the resilient full-profile egress topology with one NAT per AZ.
single_nat_gateway = false

# Accepted dev-only tradeoff: the public EKS API is reachable from the internet
# because this small team's source IPs are dynamic. IAM authentication and EKS
# access entries enforce access. Do not silently narrow this value, and do not
# copy it to staging or production; those environments require restricted CIDRs.
cluster_public_access_cidrs = ["0.0.0.0/0"]

bootstrap_admin_principal_arns = [
  "arn:aws:iam::916491575487:role/microtodosuite-terraform-dev",
]

# This account's Free Tier policy permits m7i-flex.large while preserving the
# approved non-burstable x86 baseline of 2 vCPU and 8 GiB memory.
bootstrap_node_instance_types = ["m7i-flex.large"]
# Bumped to match the release actually running on the nodegroup after the
# 2026-08-24 rolling replace (aws eks update-nodegroup-version --force, done
# to pick up VPC CNI prefix delegation on fresh nodes) - keeping this pinned
# to the older value would make Terraform revert a working nodegroup to an
# older AMI on the next apply, forcing another full node replacement.
bootstrap_node_ami_release_version = "1.35.6-20260818"

# Shared-cluster release prerequisites. These exact values are validated by the
# module; changing them requires a separate reviewed design decision.
create_shared_resources = true
shared_environments     = ["dev", "staging", "prod", "demo"]
neutral_service_names = [
  "auth-api",
  "frontend",
  "log-message-processor",
  "todos-api",
  "users-api",
]
github_oidc_subjects = [
  "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
  "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
  "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
  "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
  "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
]
environment_jwt_secret_version        = 1
kyverno_service_account_subject       = "system:serviceaccount:kyverno:kyverno-admission-controller"
observability_service_account_subject = "system:serviceaccount:observability:observability-external-secrets-jwt"
security_service_account_subject      = "system:serviceaccount:security:security-external-secrets-jwt"
