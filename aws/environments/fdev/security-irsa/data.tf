# What the fdev/security-irsa root reads rather than creates (PC-IAC-017): the OIDC issuer of
# fdev/workload's cluster and the secret containers of fdev/security, by standard name.
data "aws_partition" "current" {
  provider = aws.principal
}

data "aws_eks_cluster" "main" {
  provider = aws.principal

  name = local.cluster_name
}

data "aws_secretsmanager_secret" "jwt" {
  for_each = var.jwt_reader_namespaces
  provider = aws.principal

  name = "${local.governance_prefix}-sm-jwt${each.key}"
}

data "aws_secretsmanager_secret" "webhook" {
  for_each = local.webhook_readers
  provider = aws.principal

  name = each.value.secret_name
}

# The Karpenter prerequisites the workload root created and the node role the security root
# created: the controller polls that queue, and passes that role to the instance profiles it
# generates for the nodes it launches.
data "aws_sqs_queue" "karpenter_interruption" {
  provider = aws.principal

  name = local.karpenter_queue_name
}

data "aws_iam_role" "node" {
  provider = aws.principal

  name = local.node_role_name
}
