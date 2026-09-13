# The shd/dns root: the account's public hosted zone (PC-IAC-022). The zone already exists
# and its name servers are delegated at the registrar, so it is adopted, not created
# (ops spec 004 FR-005). Records belong to the roots that own their targets.
import {
  to = module.public_zone.aws_route53_zone.this
  id = var.public_zone_id
}

module "public_zone" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//route53-zone?ref=route53-zone-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client        = var.client
  project       = var.project
  environment   = var.environment
  zone_name     = var.public_zone_name
  standard_name = local.public_zone_standard_name
  comment       = local.public_zone_comment
}
