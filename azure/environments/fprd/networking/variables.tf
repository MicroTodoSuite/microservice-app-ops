# Inputs of the fprd/networking Azure root. Environment configuration arrives
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

variable "vnet_cidr" {
  type        = string
  description = "VNet range selected by the DR preflight from live evidence; it must overlap no AWS VPC."

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be an IPv4 CIDR block."
  }
}

variable "node_subnet_cidr" {
  type        = string
  description = "Private node subnet inside the VNet range."

  validation {
    condition     = can(cidrhost(var.node_subnet_cidr, 0))
    error_message = "node_subnet_cidr must be an IPv4 CIDR block."
  }
}

variable "reserved_cidrs" {
  type        = list(string)
  description = "Every AWS VPC of the estate; the VNet must overlap none (spec 009 FR-008)."

  validation {
    condition     = length(var.reserved_cidrs) > 0 && alltrue([for cidr in var.reserved_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Name every AWS VPC range; an empty list would let the VNet collide with AWS."
  }
}

variable "enable_active_active" {
  type        = bool
  description = "Latency-based active-active routing between AWS and Azure. It stays false until a replicated data store exists (constitution principle 12, spec 009 FR-046)."
  default     = false

  validation {
    condition     = !var.enable_active_active
    error_message = "Active-active routing cannot be enabled: no replicated data store makes a user's requests consistent across clouds (constitution principle 12)."
  }
}
