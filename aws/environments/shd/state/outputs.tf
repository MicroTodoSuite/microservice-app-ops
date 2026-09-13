# Outputs of the shd/state root: what every other root's backend configuration needs.
output "state_bucket_name" {
  description = "Name of the state bucket, the bucket value of every other root's .s3.tfbackend."
  value       = module.state_backend.bucket_name
}

output "state_bucket_arn" {
  description = "ARN of the state bucket, for the deploy role's policy."
  value       = module.state_backend.bucket_arn
}

output "state_kms_key_arn" {
  description = "ARN of the state encryption key, the kms_key_id value of every other root's .s3.tfbackend."
  value       = module.state_backend.kms_key_arn
}

output "state_kms_alias_name" {
  description = "Alias of the state encryption key."
  value       = module.state_backend.kms_alias_name
}
