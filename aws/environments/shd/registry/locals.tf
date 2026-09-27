# Names and tags of the shd/registry root, built here and nowhere else (PC-IAC-012, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  service_repositories = {
    for key in var.service_image_keys : key => { name = "${local.governance_prefix}-ecr-${key}" }
  }

  # The platform key is reserved for the mirror; var.service_image_keys rejects it.
  platform_mirror_repositories = {
    platform = { name = "${local.governance_prefix}-ecr-platform" }
  }

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
