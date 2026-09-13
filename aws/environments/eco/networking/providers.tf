# The principal provider of the eco/networking root (PC-IAC-005): bound to the declared
# account and region (MTS-IAC-103), acting through the deploy role, and tagging every
# resource with the transversal tags (PC-IAC-004).
provider "aws" {
  alias               = "principal"
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  assume_role {
    role_arn     = var.deploy_role_arn
    session_name = "${local.governance_prefix}-networking"
  }

  default_tags {
    tags = local.common_tags
  }
}
