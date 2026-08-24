resource "aws_route53_zone" "public" {
  count = var.public_hosted_zone_name == null ? 0 : 1

  name          = var.public_hosted_zone_name
  comment       = "Public hosted zone for ${var.public_hosted_zone_name}; registrar delegation remains manual."
  force_destroy = false

  tags = merge(local.tags, {
    Name = var.public_hosted_zone_name
  })
}
