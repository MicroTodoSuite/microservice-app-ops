# Names and tags of the shd/state root, built here and nowhere else (PC-IAC-025, PC-IAC-012).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  # The module appends the account ID to the bucket name (MTS-IAC-101 recorded exception).
  state_bucket_name = "${local.governance_prefix}-s3-tfstate"
  state_key_name    = "${local.governance_prefix}-kms-tfstate"

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
