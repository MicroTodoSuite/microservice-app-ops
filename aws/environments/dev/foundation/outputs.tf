output "environment" {
  description = "Environment owned by this Terraform root."
  value       = "dev"
}

output "foundation_contract" {
  description = "Reviewable dev foundation inventory."
  value       = module.foundation.foundation_contract
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
