# Inputs of the fprd/security Azure root. Environment configuration arrives
# from the operator-owned fprd.tfvars (PC-IAC-024); fprd.tfvars.example shows
# its shape.

variable "client" {
  type        = string
  description = "Client code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "The client code must be 2 to 10 lowercase letters or digits."
  }
}

variable "project" {
  type        = string
  description = "Project code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project))
    error_message = "The project code must be 2 to 15 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment code; the Azure recovery estate is fprd (MTS-IAC-101)."

  validation {
    condition     = var.environment == "fprd"
    error_message = "The Azure disaster-recovery roots belong to the fprd environment only."
  }
}

variable "subscription_id" {
  type        = string
  description = "Approved Azure subscription ID, verified by the DR preflight (spec 009 T124)."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Approved Azure region by programmatic name, verified by the DR preflight."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "location must be a programmatic Azure region name such as eastus2."
  }
}

variable "operator_cidrs" {
  type        = list(string)
  description = "The four approved operator /32 addresses (spec 009 FR-012, FR-016)."

  validation {
    condition     = length(var.operator_cidrs) == 4 && length(distinct(var.operator_cidrs)) == 4 && alltrue([for cidr in var.operator_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "Name exactly the four approved operator addresses, each a /32 block; widening the set is a separate reviewed change."
  }
}

variable "github_organization" {
  type        = string
  description = "GitHub organization whose shared .github repository runs the DR seed workflow."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_organization))
    error_message = "github_organization must be a GitHub organization name."
  }
}
