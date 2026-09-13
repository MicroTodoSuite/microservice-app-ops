# Data sources of the shd/security root: the partition and its DNS suffix, for ARNs and the
# CloudWatch Logs service principal.
data "aws_partition" "current" {
  provider = aws.principal
}
