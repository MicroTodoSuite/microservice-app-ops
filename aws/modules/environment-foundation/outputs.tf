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
    dns = {
      public_hosted_zone_name = var.public_hosted_zone_name
    }
    ecr_service_count = length(local.service_names)
    identity_mode     = "IRSA"
  }
}

output "public_hosted_zone_name" {
  description = "Registered public DNS name managed by Route 53, or null when this module instance does not own one."
  value       = one(aws_route53_zone.public[*].name)
}

output "public_hosted_zone_id" {
  description = "Route 53 public hosted-zone identifier, available after the hosted zone is applied."
  value       = one(aws_route53_zone.public[*].zone_id)
}

output "public_hosted_zone_name_servers" {
  description = "Four authoritative Route 53 name servers to configure manually at the registrar after apply."
  value       = sort(flatten(aws_route53_zone.public[*].name_servers))
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

output "neutral_ecr_repository_urls" {
  description = "Environment-neutral ECR repository URLs keyed by business service."
  value       = { for service, repository in aws_ecr_repository.neutral_services : service => repository.repository_url }
}

output "environment_jwt_secret_names" {
  description = "Non-secret Secrets Manager source names keyed by environment."
  value       = { for environment, secret in aws_secretsmanager_secret.environment_jwt : environment => secret.name }
}

output "environment_jwt_secret_arns" {
  description = "Non-secret Secrets Manager source ARNs keyed by environment."
  value       = { for environment, secret in aws_secretsmanager_secret.environment_jwt : environment => secret.arn }
}

output "environment_jwt_reader_role_arns" {
  description = "Exact External Secrets reader role ARNs keyed by environment."
  value       = { for environment, role in aws_iam_role.environment_jwt_reader : environment => role.arn }
}

output "github_actions_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider used by the reviewed-main publisher."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_ecr_publisher_role_arn" {
  description = "Exact GitHub Actions role allowed to publish neutral release artifacts."
  value       = aws_iam_role.github_ecr_publisher.arn
}

output "kyverno_ecr_verifier_role_arn" {
  description = "Exact Kyverno admission-controller role allowed to read neutral ECR artifacts."
  value       = aws_iam_role.kyverno_ecr_verifier.arn
}

output "observability_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Alertmanager Slack webhook."
  value       = aws_secretsmanager_secret.observability_slack_webhook.name
}

output "observability_slack_webhook_secret_arn" {
  description = "Non-secret Secrets Manager source ARN for the Alertmanager Slack webhook."
  value       = aws_secretsmanager_secret.observability_slack_webhook.arn
}

output "observability_secrets_reader_role_arn" {
  description = "Exact External Secrets reader role ARN for the observability namespace."
  value       = aws_iam_role.observability_secrets_reader.arn
}

output "security_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Falcosidekick Slack webhook."
  value       = aws_secretsmanager_secret.security_slack_webhook.name
}

output "security_slack_webhook_secret_arn" {
  description = "Non-secret Secrets Manager source ARN for the Falcosidekick Slack webhook."
  value       = aws_secretsmanager_secret.security_slack_webhook.arn
}

output "security_secrets_reader_role_arn" {
  description = "Exact External Secrets reader role ARN for the security namespace."
  value       = aws_iam_role.security_secrets_reader.arn
}
