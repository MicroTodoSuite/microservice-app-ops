variable "environments" {
  description = "Exact environments that receive independently generated JWT values."
  type        = set(string)

  validation {
    condition     = var.environments == toset(["dev", "staging", "prod"])
    error_message = "environments must contain exactly dev, staging, and prod."
  }
}
