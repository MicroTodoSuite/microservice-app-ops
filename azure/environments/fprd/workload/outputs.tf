# Identifiers of the DR cluster and recovery storage. No output carries a
# kubeconfig or a credential.
output "cluster_name" {
  description = "Name of the AKS DR cluster."
  value       = module.aks_cluster.cluster_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster; security-federation and the AKS-issuer IAM OIDC provider in dev owner state (T134) trust it."
  value       = module.aks_cluster.oidc_issuer_url
}

output "kubernetes_version" {
  description = "Kubernetes version of the cluster."
  value       = module.aks_cluster.kubernetes_version
}

output "api_server_authorized_cidrs" {
  description = "Addresses the API server admits, read from the cluster."
  value       = module.aks_cluster.api_server_authorized_cidrs
}

output "recovery_storage_account_name" {
  description = "Name of the encrypted recovery storage account."
  value       = module.recovery_storage.storage_account_name
}
