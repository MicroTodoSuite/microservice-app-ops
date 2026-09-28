# The shd/dns root: the account's public hosted zones (PC-IAC-022). An account that still
# owns the legacy zone can manage and adopt it without changing its delegated name servers
# (ops spec 001 T066, ops spec 004 FR-005). A fresh account omits it. The canonical zone is
# always created here. Records belong to the roots that own their targets.
import {
  for_each = var.manage_legacy_public_dns && var.adopt_existing_public_dns ? toset([var.public_zone_id]) : toset([])

  to = module.public_zone[0].aws_route53_zone.this
  id = each.value
}

module "public_zone" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//route53-zone?ref=route53-zone-v1.0.0"
  count  = var.manage_legacy_public_dns ? 1 : 0

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

# The canonical zone every profile's subdomains live in (gitops spec 009 FR-044). A new zone
# gets new name servers, so the registrar must point at this zone's, which the
# canonical_zone_name_server_names output lists.
module "canonical_zone" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//route53-zone?ref=route53-zone-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client        = var.client
  project       = var.project
  environment   = var.environment
  zone_name     = var.canonical_zone_name
  standard_name = local.canonical_zone_standard_name
  comment       = local.canonical_zone_comment
}
