locals {
  tags = merge(var.common_tags, {
    Project     = "MicroTodoSuite"
    Owner       = var.owner
    ManagedBy   = "terraform"
    Root        = "aws/shared/egress"
    Environment = "shared"
  })
}

# The egress hub is a shared singleton with its own state key. It is deliberately
# not part of any environment's foundation: an environment that could create or
# destroy the hub could take every other environment offline with it.
module "egress" {
  source = "../../modules/centralized-egress"

  name                 = var.name
  aws_region           = var.aws_region
  expected_account_id  = var.expected_account_id
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  spokes               = var.spokes

  tags = local.tags
}
