output "bucket_name" {
  description = "Environment-qualified S3 bucket for dev Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "ARN of the dev Terraform state bucket."
  value       = aws_s3_bucket.terraform_state.arn
}

output "kms_key_arn" {
  description = "ARN of the rotating KMS key used for state and lock files."
  value       = aws_kms_key.terraform_state.arn
}

output "kms_alias" {
  description = "Stable alias for the dev Terraform state KMS key."
  value       = aws_kms_alias.terraform_state.name
}

output "bootstrap_state_key" {
  description = "Reserved remote address for the backend root after a separately reviewed migration."
  value       = local.bootstrap_state_key
}

output "foundation_state_key" {
  description = "Remote state key consumed by the dev foundation root."
  value       = local.foundation_state_key
}

output "foundation_lock_key" {
  description = "Native S3 lockfile key derived from the foundation state address."
  value       = local.foundation_lock_key
}
