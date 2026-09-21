# Non-secret identifiers of the DR foundation. No output carries a credential,
# a kubeconfig, or a secret value.

output "foundation_contract_data" {
  description = "The reviewed, non-secret contract of the DR foundation, checked by tests/foundation.tftest.hcl."
  value = {
    subscription_id             = var.subscription_id
    location                    = var.location
    kubernetes_version          = module.aks_foundation.kubernetes_version
    network_policy_engine       = "azure-cni-overlay-cilium"
    api_server_authorized_cidrs = module.aks_foundation.api_server_authorized_cidrs
    network = {
      vnet_cidr        = var.vnet_cidr
      node_subnet_cidr = var.node_subnet_cidr
      pod_cidr         = var.pod_cidr
      service_cidr     = var.service_cidr
      dns_service_ip   = var.dns_service_ip
    }
    reserved_cidrs            = var.reserved_cidrs
    key_vault_name            = module.aks_foundation.key_vault_name
    key_vault_secret_names    = local.key_vault_secret_names
    key_vault_reader_subjects = [for account in values(local.key_vault_reader_service_accounts) : "system:serviceaccount:${account.namespace}:${account.name}"]
    github_seed_subjects      = local.github_seed_subjects
    ingress = {
      public_ip_name      = module.aks_foundation.ingress_public_ip_name
      resource_group_name = module.aks_foundation.ingress_public_ip_resource_group_name
      endpoint            = module.aks_foundation.ingress_public_ip_endpoint
      dns_name            = module.aks_foundation.ingress_public_ip_dns_name
    }
    active_active_enabled = var.enable_active_active
  }
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = module.aks_foundation.cluster_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster; the AKS-issuer IAM OIDC provider in dev owner state trusts it (T134)."
  value       = module.aks_foundation.oidc_issuer_url
}

output "key_vault_name" {
  description = "Name of the empty DR Key Vault, the seed workflow's only target."
  value       = module.aks_foundation.key_vault_name
}

output "key_vault_url" {
  description = "Data-plane URL of the DR Key Vault, for the Azure secret store (T129)."
  value       = module.aks_foundation.key_vault_url
}

output "key_vault_reader_client_id" {
  description = "Client ID of the reader identity the External Secrets service accounts carry."
  value       = module.aks_foundation.key_vault_reader_client_id
}

output "github_seed_client_id" {
  description = "Client ID the seed workflow federates to."
  value       = module.aks_foundation.github_seed_client_id
}

output "container_registry_endpoint" {
  description = "Login server of the DR registry, the mirror workflows' target (T131)."
  value       = module.aks_foundation.container_registry_endpoint
}

output "ingress_public_ip_name" {
  description = "Name of the static ingress public IP, for the azure-pip-name Service annotation (T129)."
  value       = module.aks_foundation.ingress_public_ip_name
}

output "ingress_public_ip_resource_group_name" {
  description = "Resource group of the static ingress public IP, for the azure-load-balancer-resource-group Service annotation (T129)."
  value       = module.aks_foundation.ingress_public_ip_resource_group_name
}

output "ingress_public_ip_endpoint" {
  description = "IPv4 address of the static ingress public IP."
  value       = module.aks_foundation.ingress_public_ip_endpoint
}

output "ingress_public_ip_dns_name" {
  description = "Provider FQDN of the static ingress public IP, the CNAME target of full-prod-azure.microtodosuite.online (T134)."
  value       = module.aks_foundation.ingress_public_ip_dns_name
}
