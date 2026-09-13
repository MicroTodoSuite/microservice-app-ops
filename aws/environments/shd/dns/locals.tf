# Names and tags of the shd/dns root, built here and nowhere else (PC-IAC-012, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  public_zone_standard_name = "${local.governance_prefix}-dns-public"
  # The legacy root's comment, kept word for word so that adopting the zone changes only
  # its tags.
  public_zone_comment = "Public hosted zone for ${var.public_zone_name}; registrar delegation remains manual."

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repository  = var.repository
  }
}
