# Data sources of the shd/security root: the partition and its DNS suffix, for ARNs and the
# CloudWatch Logs service principal.
data "aws_partition" "current" {
  provider = aws.principal
}

# shd/state's Terraform state bucket, by the name PC-IAC-008 gives it; the state trail records
# every read and write of its objects.
data "aws_s3_bucket" "state" {
  provider = aws.principal

  bucket = local.state_bucket_name
}
