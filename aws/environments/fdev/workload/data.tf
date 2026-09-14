# What the fdev/workload root reads rather than creates (PC-IAC-017): the network of
# fdev/networking and the roles, keys, and security groups of fdev/security, each found by its
# standard name.
data "aws_partition" "current" {
  provider = aws.principal
}

data "aws_vpc" "main" {
  provider = aws.principal

  tags = { Name = local.vpc_name }
}

# The private subnets carry the cluster's discovery tag and the internal load balancer role.
data "aws_subnets" "private" {
  provider = aws.principal

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "The cluster needs private subnets in at least two Availability Zones, and fdev/networking tags one per zone."
    }
  }
}

data "aws_security_group" "cluster" {
  provider = aws.principal

  vpc_id = data.aws_vpc.main.id
  name   = local.cluster_security_group_name
}

data "aws_security_group" "node" {
  provider = aws.principal

  vpc_id = data.aws_vpc.main.id
  name   = local.node_security_group_name
}

data "aws_iam_role" "cluster" {
  provider = aws.principal

  name = local.cluster_role_name
}

data "aws_iam_role" "node" {
  provider = aws.principal

  name = local.node_role_name
}

data "aws_iam_role" "addon" {
  for_each = local.addon_role_names
  provider = aws.principal

  name = each.value
}

data "aws_kms_alias" "secrets" {
  provider = aws.principal

  name = "alias/${local.secrets_key_name}"
}

data "aws_kms_alias" "logs" {
  provider = aws.principal

  name = "alias/${local.logs_key_name}"
}
