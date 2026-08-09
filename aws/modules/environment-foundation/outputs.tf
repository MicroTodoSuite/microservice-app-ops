output "foundation_contract" {
  description = "Reviewable inventory of the dev-only foundation implemented by User Story 1."
  value = {
    environment = var.environment
    network = {
      az_count                    = length(var.availability_zones)
      private_worker_subnet_count = length(module.vpc.private_subnets)
      public_subnet_count         = length(module.vpc.public_subnets)
      nat_gateway_count           = length(module.vpc.natgw_ids)
    }
    eks = {
      kubernetes_version      = var.kubernetes_version
      endpoint_private_access = true
      endpoint_public_access  = true
      node_group = {
        min           = var.bootstrap_node_min_size
        desired       = var.bootstrap_node_desired_size
        max           = var.bootstrap_node_max_size
        capacity_type = "ON_DEMAND"
        ami_type      = "AL2023_x86_64_STANDARD"
      }
    }
    ecr_service_count = length(local.service_names)
    identity_mode     = "IRSA"
  }
}

output "vpc_id" {
  description = "Dev VPC identifier."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Dev VPC IPv4 CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability zones selected for the dev foundation."
  value       = var.availability_zones
}

output "public_subnet_ids" {
  description = "Public load-balancer and NAT subnet identifiers."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private EKS workload subnet identifiers."
  value       = module.vpc.private_subnets
}

output "nat_gateway_ids" {
  description = "One zonal NAT gateway identifier per selected availability zone."
  value       = module.vpc.natgw_ids
}

output "vpc_flow_log_id" {
  description = "VPC flow log identifier."
  value       = module.vpc.vpc_flow_log_id
}

output "vpc_flow_log_destination_arn" {
  description = "Encrypted CloudWatch Logs destination for VPC flow logs."
  value       = module.vpc.vpc_flow_log_destination_arn
}

output "vpc_flow_log_kms_key_arn" {
  description = "KMS key used to encrypt the VPC flow-log group."
  value       = aws_kms_key.vpc_flow_logs.arn
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint for operator and one-time bootstrap use."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS certificate authority for operator bootstrap."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "EKS-created primary cluster security group identifier."
  value       = module.eks.cluster_primary_security_group_id
}

output "karpenter_security_group_id" {
  description = "Single EKS node security group tagged for future Karpenter discovery."
  value       = module.eks.node_security_group_id
}

output "oidc_issuer_url" {
  description = "EKS OIDC issuer URL."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by IRSA."
  value       = module.eks.oidc_provider_arn
}

output "vpc_cni_irsa_role_arn" {
  description = "Exact kube-system/aws-node IRSA role ARN."
  value       = aws_iam_role.vpc_cni.arn
}

output "node_role_arn" {
  description = "Limited IAM role used by stable bootstrap nodes."
  value       = aws_iam_role.node.arn
}

output "bootstrap_node_group_id" {
  description = "Stable managed bootstrap node-group identifier."
  value       = module.bootstrap_node_group.node_group_id
}

output "bootstrap_node_group_arn" {
  description = "Stable managed bootstrap node-group ARN."
  value       = module.bootstrap_node_group.node_group_arn
}

output "bootstrap_node_group_status" {
  description = "Stable managed bootstrap node-group status."
  value       = module.bootstrap_node_group.node_group_status
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by the five current service names."
  value       = { for service, repository in aws_ecr_repository.services : service => repository.repository_url }
}
