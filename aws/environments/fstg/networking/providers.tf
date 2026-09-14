# The principal provider is restricted to the declared account and assumes the
# reviewed deployment role before it changes the fstg spoke.
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
