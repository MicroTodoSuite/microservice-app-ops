# Outputs of the shd/dns root, read by the roots that own records in the zone.
output "public_zone_id" {
  description = "Hosted zone ID of the legacy public zone, or null when it is unmanaged."
  value       = try(module.public_zone[0].zone_id, null)
}

output "public_zone_arn" {
  description = "ARN of the legacy public zone, or null when it is unmanaged."
  value       = try(module.public_zone[0].zone_arn, null)
}

output "public_zone_name_server_names" {
  description = "Name servers of the legacy public zone, or null when it is unmanaged."
  value       = try(module.public_zone[0].name_server_names, null)
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

output "destination_record_names" {
  description = "Name of each enabled destination CNAME in the canonical zone, keyed by destination; empty until a provider FQDN is supplied."
  value       = { for key, record in aws_route53_record.destination : key => record.fqdn }
}

output "destination_health_check_ids" {
  description = "Route 53 health check ID of each enabled workload destination, keyed by destination."
  value       = { for key, check in aws_route53_health_check.destination : key => check.id }
}
