# What the eco/networking root reads rather than creates (PC-IAC-017): the zones it spans,
# and the flow-log key and role that shd/security owns, found by their standard names.

# EKS refuses cluster subnets in a few zone IDs, and a zone name maps to a different zone
# ID in every account, so the check reads the ID the account sees (EKS user guide, subnet
# requirements).
data "aws_availability_zone" "selected" {
  for_each = toset(var.availability_zones)
  provider = aws.principal

  name = each.value

  lifecycle {
    postcondition {
      condition     = self.zone_type == "availability-zone" && !contains(local.eks_disallowed_zone_ids, self.zone_id)
      error_message = "Every zone must be an Availability Zone whose zone ID EKS accepts for cluster subnets."
    }
  }
}

data "aws_kms_alias" "flow_log" {
  provider = aws.principal

  name = "alias/${local.shared_prefix}-kms-flowlogs"
}

data "aws_iam_role" "flow_log" {
  provider = aws.principal

  name = "${local.shared_prefix}-role-flowlogs"
}
