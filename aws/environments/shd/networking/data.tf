# What the shd/networking root reads rather than creates (PC-IAC-017): its
# Availability Zone and the flow-log key and role that shd/security owns.
data "aws_availability_zone" "selected" {
  for_each = toset(var.availability_zones)
  provider = aws.principal

  name = each.value

  lifecycle {
    postcondition {
      condition     = self.zone_type == "availability-zone"
      error_message = "The hub zone must be an Availability Zone, not a Local or Wavelength Zone."
    }
  }
}

data "aws_kms_alias" "flow_log" {
  provider = aws.principal

  name = "alias/${local.governance_prefix}-kms-flowlogs"
}

data "aws_iam_role" "flow_log" {
  provider = aws.principal

  name = "${local.governance_prefix}-role-flowlogs"
}
