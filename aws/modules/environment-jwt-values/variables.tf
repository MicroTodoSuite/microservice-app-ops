variable "environments" {
  description = "Environments that receive independently generated JWT values. Driven by the caller's shared_environments so new environments are added by list, not by editing this module."
  type        = set(string)

  validation {
    condition     = length(var.environments) > 0
    error_message = "environments must not be empty."
  }

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z0-9-]+$", e))])
    error_message = "environments elements must be DNS-safe strings."
  }
}
