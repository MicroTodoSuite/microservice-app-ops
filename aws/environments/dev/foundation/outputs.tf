output "environment" {
  description = "Environment owned by this Terraform root."
  value       = "dev"
}

output "foundation_contract" {
  description = "Reviewable dev foundation inventory."
  value       = module.foundation.foundation_contract
}

output "public_hosted_zone_name" {
  description = "Registered public DNS name managed by Route 53."
  value       = module.foundation.public_hosted_zone_name
}

output "public_hosted_zone_id" {
  description = "Route 53 public hosted-zone identifier, available after apply."
  value       = module.foundation.public_hosted_zone_id
}

output "public_hosted_zone_name_servers" {
  description = "Four authoritative Route 53 name servers to configure manually at the registrar after apply."
  value       = module.foundation.public_hosted_zone_name_servers
}

output "vpc_id" {
  description = "Dev VPC identifier."
  value       = module.foundation.vpc_id
}

output "availability_zones" {
  description = "Availability zones selected for the dev foundation."
  value       = module.foundation.availability_zones
}

output "public_subnet_ids" {
  description = "Public load-balancer and NAT subnet identifiers."
  value       = module.foundation.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private EKS workload subnet identifiers."
  value       = module.foundation.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "Zonal NAT gateway identifiers."
  value       = module.foundation.nat_gateway_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.foundation.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.foundation.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint for operator and one-time bootstrap use."
  value       = module.foundation.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS certificate authority for operator bootstrap."
  value       = module.foundation.cluster_certificate_authority_data
}

output "bootstrap_node_group_arn" {
  description = "Stable managed bootstrap node-group ARN."
  value       = module.foundation.bootstrap_node_group_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name."
  value       = module.foundation.ecr_repository_urls
}

output "neutral_ecr_repository_urls" {
  description = "Environment-neutral ECR repository URLs keyed by business service."
  value       = module.foundation.neutral_ecr_repository_urls
}

output "environment_jwt_secret_names" {
  description = "Non-secret Secrets Manager source names keyed by environment."
  value       = module.foundation.environment_jwt_secret_names
}

output "environment_jwt_secret_arns" {
  description = "Non-secret Secrets Manager source ARNs keyed by environment."
  value       = module.foundation.environment_jwt_secret_arns
}

output "environment_jwt_reader_role_arns" {
  description = "Exact External Secrets reader role ARNs keyed by environment."
  value       = module.foundation.environment_jwt_reader_role_arns
}

output "github_actions_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = module.foundation.github_actions_oidc_provider_arn
}

output "github_ecr_publisher_role_arn" {
  description = "Reviewed-main neutral ECR publisher role ARN."
  value       = module.foundation.github_ecr_publisher_role_arn
}

output "kyverno_ecr_verifier_role_arn" {
  description = "Kyverno private-ECR verifier role ARN."
  value       = module.foundation.kyverno_ecr_verifier_role_arn
}

output "observability_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Alertmanager Slack webhook."
  value       = module.foundation.observability_slack_webhook_secret_name
}

output "observability_secrets_reader_role_arn" {
  description = "Observability namespace External Secrets reader role ARN."
  value       = module.foundation.observability_secrets_reader_role_arn
}

output "security_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Falcosidekick Slack webhook."
  value       = module.foundation.security_slack_webhook_secret_name
}

output "security_secrets_reader_role_arn" {
  description = "Security namespace External Secrets reader role ARN."
  value       = module.foundation.security_secrets_reader_role_arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by IRSA."
  value       = module.foundation.oidc_provider_arn
}

output "vpc_cni_irsa_role_arn" {
  description = "Exact kube-system/aws-node IRSA role ARN."
  value       = module.foundation.vpc_cni_irsa_role_arn
}

output "node_role_arn" {
  description = "Limited IAM role used by stable bootstrap nodes."
  value       = module.foundation.node_role_arn
}

output "karpenter_security_group_id" {
  description = "Single node security group tagged for future Karpenter discovery."
  value       = module.foundation.karpenter_security_group_id
}
