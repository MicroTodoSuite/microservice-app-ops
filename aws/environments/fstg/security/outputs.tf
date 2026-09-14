# Outputs of the fstg/security root, read by fstg/workload and the IRSA pass.
output "cluster_role_arn" {
  description = "ARN of the control-plane role."
  value       = module.cluster_role.role_arn
}

output "node_role_arn" {
  description = "ARN of the managed nodes' role."
  value       = module.node_role.role_arn
}

output "addon_role_arns" {
  description = "Pod Identity role ARNs of the cluster add-ons, keyed by vpccni and ebscsi."
  value       = { for key, role in module.addon_roles : key => role.role_arn }
}

output "secrets_key_arn" {
  description = "ARN of the key that encrypts the cluster's Kubernetes secrets."
  value       = module.secrets_key.key_arn
}

output "logs_key_arn" {
  description = "ARN of the key that encrypts the control-plane log group."
  value       = module.logs_key.key_arn
}

output "cluster_security_group_id" {
  description = "ID of the extra control-plane security group."
  value       = module.cluster_security_group.security_group_id
}

output "node_security_group_id" {
  description = "ID of the node security group."
  value       = module.node_security_group.security_group_id
}

output "jwt_secret_arns" {
  description = "JWT signing secret ARNs keyed by application environment code."
  value       = { for code, secret in module.jwt_secrets : code => secret.secret_arn }
}

output "webhook_secret_arns" {
  description = "Slack webhook secret ARNs keyed by slackobs and slacksec."
  value       = { for key, secret in module.webhook_secrets : key => secret.secret_arn }
}
