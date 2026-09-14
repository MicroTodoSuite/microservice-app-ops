# Outputs of the fstg/workload root, read by the IRSA pass, the GitOps bootstrap, and kubeconfig.
output "cluster_name" {
  description = "Name of the full-staging cluster."
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "ARN of the full-staging cluster."
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

output "karpenter_interruption_queue_name" {
  description = "Name of the Karpenter interruption queue, the value the controller's interruption queue setting takes."
  value       = module.karpenter_interruption.queue_name
}

output "karpenter_interruption_queue_arn" {
  description = "ARN of the Karpenter interruption queue, which the IRSA pass grants the controller."
  value       = module.karpenter_interruption.queue_arn
}

output "karpenter_node_role_name" {
  description = "Name of the role the EC2NodeClass gives the instance profiles Karpenter generates: the bootstrap node group's role, which Amazon EKS already authorized on the cluster through its access entry."
  value       = data.aws_iam_role.node.name
}
