resource "aws_route53_zone" "public" {
  count = var.public_hosted_zone_name == null ? 0 : 1

  name          = var.public_hosted_zone_name
  comment       = "Public hosted zone for ${var.public_hosted_zone_name}; registrar delegation remains manual."
  force_destroy = false

  tags = merge(local.tags, {
    Name = var.public_hosted_zone_name
  })
}

# ---------------------------------------------------------------------------
# Canonical domain (spec 009, T019).
#
# microtodosuite.online lives at its OWN resource address, deliberately not as a
# new value for public_hosted_zone_name. aws_route53_zone.name forces
# replacement, so renaming the legacy zone in place would destroy it, drop every
# record it holds, and invalidate the name-server delegation configured at the
# registrar. Both zones therefore coexist, and the legacy zone is never a
# cleanup target for the canonical rollout.
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "canonical" {
  count = var.create_canonical_hosted_zone ? 1 : 0

  name          = local.canonical_hosted_zone_name
  comment       = "Canonical public hosted zone for ${local.canonical_hosted_zone_name}; registrar delegation remains manual."
  force_destroy = false

  tags = merge(local.tags, {
    Name = local.canonical_hosted_zone_name
  })
}

# Application traffic on the canonical domain is a separate named approval taken
# after the DR game day. Until a traffic owner supplies a reviewed destination,
# this map is empty and no record exists.
resource "aws_route53_record" "canonical_destination" {
  for_each = var.create_canonical_hosted_zone ? var.canonical_destination_records : {}

  zone_id = aws_route53_zone.canonical[0].zone_id
  name    = "${each.key}.${local.canonical_hosted_zone_name}"
  type    = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}
