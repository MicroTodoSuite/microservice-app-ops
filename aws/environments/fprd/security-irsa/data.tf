# What the fprd/security-irsa root reads rather than creates (PC-IAC-017): the OIDC issuer of
# fprd/workload's cluster and the secret containers of fprd/security, by standard name.
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
