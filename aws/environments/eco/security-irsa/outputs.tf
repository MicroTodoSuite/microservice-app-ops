# Outputs of the eco/security-irsa root, the role ARNs the GitOps service-account annotations
# take (ops spec 004 T016).
output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider of the economical cluster's issuer."
  value       = module.eks_oidc.provider_arn
}

output "irsa_role_arns" {
  description = "IRSA role ARNs keyed by role key: jwt<code>, obssecret, secsecret, trivyecr, kyvernoecr, and lbcontrol."
  value       = { for key, role in module.irsa_roles : key => role.role_arn }
}
