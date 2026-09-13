# What the eco/security root reads rather than creates (PC-IAC-017): the partition, and the
# VPC that eco/networking owns, found by its standard name.
data "aws_partition" "current" {
  provider = aws.principal
}

data "aws_vpc" "main" {
  provider = aws.principal

  tags = { Name = local.vpc_name }
}
