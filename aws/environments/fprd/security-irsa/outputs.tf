# Outputs of the fprd/security-irsa root, the role ARNs the GitOps service-account annotations
# take (ops spec 004 T016).
output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider of the full production cluster's issuer."
  value       = module.eks_oidc.provider_arn
}

output "irsa_role_arns" {
  description = "IRSA role ARNs keyed by role key: jwt<code>, obssecret, secsecret, trivyecr, kyvernoecr, karpenter, and lbcontrol."
  value       = { for key, role in module.irsa_roles : key => role.role_arn }
}

output "aks_oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider of the AKS disaster-recovery cluster's issuer, or null while the DNS-01 solvers are disabled."
  value       = one(module.aks_oidc[*].provider_arn)
}

output "dns01_role_arns" {
  description = "DNS-01 solver role ARNs keyed by dns01aws and dns01aks, the cert-manager service-account annotations of T139; empty while the solvers are disabled."
  value       = { for key, role in module.dns01_roles : key => role.role_arn }
}
