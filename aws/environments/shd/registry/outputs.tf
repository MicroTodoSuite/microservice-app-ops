# Outputs of the shd/registry root, read by the GitOps values and the environment roots.
output "service_repository_urls" {
  description = "Repository URLs keyed by service key, the image names the GitOps values use."
  value       = module.service_images.repository_urls
}

output "service_repository_arns" {
  description = "Repository ARNs keyed by service key, for pull permissions in the environment roots."
  value       = module.service_images.repository_arns
}
