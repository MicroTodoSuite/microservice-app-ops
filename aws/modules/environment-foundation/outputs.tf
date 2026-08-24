output "foundation_contract" {
  description = "Reviewable inventory of the dev-only foundation implemented by User Story 1."
  value = {
    environment = var.environment
    network = {
      az_count                    = length(var.availability_zones)
      private_worker_subnet_count = length(module.vpc.private_subnets)
      public_subnet_count         = length(module.vpc.public_subnets)
      nat_gateway_count           = length(module.vpc.natgw_ids)

      outbound_mode              = var.outbound_mode
      nat_gateway_enabled        = local.nat_gateway_enabled
      transit_gateway_id         = var.transit_gateway_id
      transit_egress_route_count = length(aws_route.private_transit_egress)

      # The internet gateway exists in both modes, but in transit-egress it is
      # reachable only from the public load-balancer subnets.
      internet_gateway_serves_public_load_balancers = true
      map_public_ip_on_launch                       = false

      public_load_balancer_subnet_tags  = local.public_load_balancer_subnet_tags
      private_load_balancer_subnet_tags = local.private_load_balancer_subnet_tags
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
      public_hosted_zone_name            = var.public_hosted_zone_name
      canonical_hosted_zone_name         = one(aws_route53_zone.canonical[*].name)
      canonical_hosted_zone_enabled      = var.create_canonical_hosted_zone
      canonical_destination_record_count = length(aws_route53_record.canonical_destination)
    }
    cluster_prerequisites = {
      enabled = var.enable_full_profile_cluster_prerequisites

      # The EBS CSI driver is an unconditional baseline for both profiles: the
      # in-tree AWS EBS provisioner no longer exists on Kubernetes 1.35.
      ebs_csi_driver = true

      karpenter_controller_role_arn         = one(module.karpenter[*].iam_role_arn)
      karpenter_node_role_arn               = one(module.karpenter[*].node_iam_role_arn)
      karpenter_interruption_queue_arn      = one(module.karpenter[*].queue_arn)
      karpenter_interruption_rule_count     = var.enable_full_profile_cluster_prerequisites ? length(module.karpenter[0].event_rules) : 0
      aws_load_balancer_controller_role_arn = one(aws_iam_role.aws_load_balancer_controller[*].arn)
    }
    ecr_service_count = length(local.service_names)
    identity_mode     = "IRSA"
  }
}

output "aws_load_balancer_controller_discovery" {
  description = "VPC- and cluster-scoped inputs the GitOps-owned AWS Load Balancer Controller needs, plus the exact subnet tags it discovers."
  value = {
    cluster_name        = module.eks.cluster_name
    vpc_id              = module.vpc.vpc_id
    region              = var.aws_region
    role_arn            = one(aws_iam_role.aws_load_balancer_controller[*].arn)
    service_account     = var.aws_load_balancer_controller_service_account_subject
    public_subnet_tags  = local.public_load_balancer_subnet_tags
    private_subnet_tags = local.private_load_balancer_subnet_tags
  }
}

output "karpenter_controller_role_arn" {
  description = "Karpenter controller IRSA role ARN, or null when the full-profile prerequisites are disabled."
  value       = one(module.karpenter[*].iam_role_arn)
}

output "karpenter_node_role_arn" {
  description = "IAM role assumed by Karpenter-launched nodes, or null when the full-profile prerequisites are disabled."
  value       = one(module.karpenter[*].node_iam_role_arn)
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile a GitOps-owned EC2NodeClass references, or null when the full-profile prerequisites are disabled."
  value       = one(module.karpenter[*].instance_profile_name)
}

output "karpenter_interruption_queue_name" {
  description = "Per-cluster Karpenter interruption queue name, or null when the full-profile prerequisites are disabled."
  value       = one(module.karpenter[*].queue_name)
}

output "karpenter_interruption_queue_kms_key_arn" {
  description = "Customer-managed key encrypting the Karpenter interruption queue, or null when the full-profile prerequisites are disabled."
  value       = one(aws_kms_key.karpenter_interruption[*].arn)
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

output "canonical_hosted_zone_name" {
  description = "Canonical public DNS name owned by this foundation, or null when this instance does not own it."
  value       = one(aws_route53_zone.canonical[*].name)
}

output "canonical_hosted_zone_id" {
  description = "Canonical Route 53 public hosted-zone identifier, available after the zone is applied."
  value       = one(aws_route53_zone.canonical[*].zone_id)
}

output "canonical_hosted_zone_name_servers" {
  description = "Four authoritative Route 53 name servers to configure manually at the registrar for the canonical domain."
  value       = sort(flatten(aws_route53_zone.canonical[*].name_servers))
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
  description = "NAT gateway identifiers for the selected per-AZ or shared topology."
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
  value       = local.neutral_ecr_repository_urls
}

output "platform_mirror_repository_url" {
  description = "URL of the single third-party platform image mirror, or null when the mirror is not in use."
  value       = local.platform_mirror_repository_url
}

output "platform_mirror_role_arn" {
  description = "Role assumed by the reviewed mirror workflow, or null when this foundation does not own the mirror."
  value       = one(aws_iam_role.github_platform_mirror[*].arn)
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
  value       = local.github_actions_oidc_provider_arn
}

output "github_ecr_publisher_role_arn" {
  description = "Exact GitHub Actions role allowed to publish neutral release artifacts."
  value       = local.github_ecr_publisher_role_arn
}

output "kyverno_ecr_verifier_role_arn" {
  description = "Exact Kyverno admission-controller role allowed to read neutral ECR artifacts."
  value       = local.kyverno_ecr_verifier_role_arn
}

output "observability_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Alertmanager Slack webhook."
  value       = local.observability_slack_webhook_secret_name
}

output "observability_slack_webhook_secret_arn" {
  description = "Non-secret Secrets Manager source ARN for the Alertmanager Slack webhook."
  value       = local.observability_slack_webhook_secret_arn
}

output "observability_secrets_reader_role_arn" {
  description = "Exact External Secrets reader role ARN for the observability namespace."
  value       = local.observability_secrets_reader_role_arn
}

output "security_slack_webhook_secret_name" {
  description = "Non-secret Secrets Manager source name for the Falcosidekick Slack webhook."
  value       = local.security_slack_webhook_secret_name
}

output "security_slack_webhook_secret_arn" {
  description = "Non-secret Secrets Manager source ARN for the Falcosidekick Slack webhook."
  value       = local.security_slack_webhook_secret_arn
}

output "security_secrets_reader_role_arn" {
  description = "Exact External Secrets reader role ARN for the security namespace."
  value       = local.security_secrets_reader_role_arn
}
