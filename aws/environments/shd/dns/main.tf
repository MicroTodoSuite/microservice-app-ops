# The shd/dns root: the account's public hosted zones (PC-IAC-022). The legacy zone already
# exists and its name servers are delegated at the registrar, so it is adopted, not created
# (ops spec 004 FR-005); the canonical zone is created here. Records belong to the roots
# that own their targets.
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
