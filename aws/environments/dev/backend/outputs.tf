output "bucket_name" {
  description = "Environment-qualified S3 bucket for dev Terraform state."
  value       = module.state_backend.bucket_name
}

output "bucket_arn" {
  description = "ARN of the dev Terraform state bucket."
  value       = module.state_backend.bucket_arn
}

output "kms_key_arn" {
  description = "ARN of the rotating KMS key used for state and lock files."
  value       = module.state_backend.kms_key_arn
}

output "kms_alias" {
  description = "Stable alias for the dev Terraform state KMS key."
  value       = module.state_backend.kms_alias
}

output "bootstrap_state_key" {
  description = "Reserved remote address for a later reviewed backend-root migration."
  value       = module.state_backend.bootstrap_state_key
}

output "foundation_state_key" {
  description = "Remote state key consumed by the dev foundation root."
  value       = module.state_backend.foundation_state_key
}

output "foundation_lock_key" {
  description = "Native S3 lockfile key used when the dev foundation locks state."
  value       = module.state_backend.foundation_lock_key
}
