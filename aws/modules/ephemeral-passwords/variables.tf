variable "names" {
  description = "Keys that each receive an independently generated ephemeral password. May be empty, so a caller can hold the module in place while the feature it feeds is still disabled."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for name in var.names : can(regex("^[a-z0-9_-]+$", name))])
    error_message = "names elements must be lowercase keys."
  }
}
