# Outputs of the eco/workload root, read by the IRSA pass, the GitOps bootstrap, and kubeconfig.
output "cluster_name" {
  description = "Name of the economical cluster."
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "ARN of the economical cluster."
  value       = module.eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data of the cluster, for kubeconfig."
  value       = module.eks_cluster.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "Issuer URL of the cluster's OpenID Connect provider, which the IRSA pass registers."
  value       = module.eks_cluster.oidc_issuer_url
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = module.eks_cluster.cluster_version
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group Amazon EKS created."
  value       = module.eks_cluster.cluster_security_group_id
}

output "node_group_arn" {
  description = "ARN of the bootstrap node group."
  value       = module.bootstrap_node_group.node_group_arn
}

output "ingress_certificate_arn" {
  description = "ARN of the ACM certificate for the economical host and its subdomains, which the load balancer controller discovers by host; null until the delegation is verified."
  value       = one(aws_acm_certificate_validation.ingress[*].certificate_arn)
}

output "ingress_record_names" {
  description = "Names published as aliases of the shared load balancer; empty until the economical Ingresses create it."
  value       = sort([for record in aws_route53_record.ingress : record.name])
}
