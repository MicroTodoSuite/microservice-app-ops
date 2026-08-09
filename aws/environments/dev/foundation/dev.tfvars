# Human-approved, non-secret dev foundation configuration shared by the team.
expected_account_id = "995253610162"
aws_region          = "us-east-1"

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

# Accepted dev-only tradeoff: the public EKS API is reachable from the internet
# because this small team's source IPs are dynamic. IAM authentication and EKS
# access entries enforce access. Do not silently narrow this value, and do not
# copy it to staging or production; those environments require restricted CIDRs.
cluster_public_access_cidrs = ["0.0.0.0/0"]

bootstrap_admin_principal_arns = [
  "arn:aws:iam::995253610162:role/microtodosuite-terraform-dev",
]

bootstrap_node_instance_types = ["m6i.large"]
