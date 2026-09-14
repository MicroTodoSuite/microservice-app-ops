# Outputs of the shd/security root, read by the environment roots.
output "github_oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider."
  value       = module.github_oidc.provider_arn
}

output "deploy_role_arn" {
  description = "ARN of the Terraform deploy role, the deploy_role_arn every rebuilt root assumes once it exists."
  value       = module.deploy_role.role_arn
}

output "ecr_publisher_role_arn" {
  description = "ARN of the role the services' main-branch workflows assume to push images."
  value       = module.ecr_publisher_role.role_arn
}

output "flow_log_key_arn" {
  description = "ARN of the key that encrypts every environment's VPC flow-log group, the network module's flow_log.kms_key_arn."
  value       = module.flow_log_key.key_arn
}

output "flow_log_role_arn" {
  description = "ARN of the role that delivers VPC flow logs, the network module's flow_log.iam_role_arn."
  value       = module.flow_log_role.role_arn
}
