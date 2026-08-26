output "environment" {
  description = "Environment this root owns."
  value       = var.environment
}

output "foundation_contract" {
  description = "Reviewable inventory of what this root builds. A stage gate compares this against the approved plan."
  value       = module.foundation.foundation_contract
}

output "vpc_id" {
  description = "full-prod VPC id. The spoke's own transit gateway attachment is created against this VPC."
  value       = module.foundation.vpc_id
}

output "vpc_cidr" {
  description = "full-prod address space. The hub installs its return route to exactly this range."
  value       = module.foundation.vpc_cidr
}

output "availability_zones" {
  description = "Availability zones in use."
  value       = module.foundation.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnets. Load balancers only; no worker receives a public address."
  value       = module.foundation.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private worker subnets."
  value       = module.foundation.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "Empty by design: a transit-egress spoke consumes no NAT gateway and no Elastic IP."
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
  description = "EKS API server endpoint."
  value       = module.foundation.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA bundle."
  value       = module.foundation.cluster_certificate_authority_data
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer. The dev owner root adds this issuer to the shared roles' trust policies."
  value       = module.foundation.oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for this cluster."
  value       = module.foundation.oidc_provider_arn
}

output "bootstrap_node_group_arn" {
  description = "Bootstrap node group ARN."
  value       = module.foundation.bootstrap_node_group_arn
}

output "node_role_arn" {
  description = "IAM role assumed by bootstrap nodes."
  value       = module.foundation.node_role_arn
}

output "vpc_cni_irsa_role_arn" {
  description = "VPC CNI IRSA role ARN."
  value       = module.foundation.vpc_cni_irsa_role_arn
}

output "karpenter_security_group_id" {
  description = "Security group Karpenter-launched nodes join."
  value       = module.foundation.karpenter_security_group_id
}

output "karpenter_controller_role_arn" {
  description = "Karpenter controller IRSA role ARN."
  value       = module.foundation.karpenter_controller_role_arn
}

output "karpenter_node_role_arn" {
  description = "IAM role assumed by Karpenter-launched nodes."
  value       = module.foundation.karpenter_node_role_arn
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile for Karpenter-launched nodes."
  value       = module.foundation.karpenter_node_instance_profile_name
}

output "karpenter_interruption_queue_name" {
  description = "Queue Karpenter watches for instance interruption notices."
  value       = module.foundation.karpenter_interruption_queue_name
}

output "aws_load_balancer_controller_discovery" {
  description = "Inputs the GitOps-owned AWS Load Balancer Controller needs, including the exact subnet tags it discovers."
  value       = module.foundation.aws_load_balancer_controller_discovery
}

# The consumer boundary, published as values a stage gate can read. Each of
# these must be empty: a non-empty result means this consumer created a second
# copy of something the dev owner root already owns.

output "environment_jwt_secret_names" {
  description = "Empty by design: a consumer creates no secret containers."
  value       = module.foundation.environment_jwt_secret_names
}

output "environment_jwt_reader_role_arns" {
  description = "Empty by design: the per-environment owner readers belong to the owner root."
  value       = module.foundation.environment_jwt_reader_role_arns
}

output "ecr_repository_urls" {
  description = "Empty by design: ECR repositories are shared and owned by the dev root."
  value       = module.foundation.ecr_repository_urls
}

output "github_actions_oidc_provider_arn" {
  description = "Null by design: the GitHub OIDC provider is an account-level singleton owned by the dev root."
  value       = module.foundation.github_actions_oidc_provider_arn
}

output "consumer_jwt_reader_role_arn" {
  description = "The single cluster-qualified reader that lets this cluster's External Secrets resolve the dev JWT secret, and nothing else."
  value       = module.foundation.consumer_jwt_reader_role_arn
}
