# Outputs of the shd/dns root, read by the roots that own records in the zone.
output "public_zone_id" {
  description = "Hosted zone ID of the public zone."
  value       = module.public_zone.zone_id
}

output "public_zone_arn" {
  description = "ARN of the public zone."
  value       = module.public_zone.zone_arn
}

output "public_zone_name_server_names" {
  description = "Name servers of the public zone, the ones delegated at the registrar."
  value       = module.public_zone.name_server_names
}

output "canonical_zone_id" {
  description = "Hosted zone ID of the canonical zone, which the roots that own its records read."
  value       = module.canonical_zone.zone_id
}

output "canonical_zone_arn" {
  description = "ARN of the canonical zone."
  value       = module.canonical_zone.zone_arn
}

output "canonical_zone_name_server_names" {
  description = "Name servers of the canonical zone, the ones the registrar must delegate to."
  value       = module.canonical_zone.name_server_names
}
