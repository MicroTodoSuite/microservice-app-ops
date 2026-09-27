# Inputs of the Azure DR foundation root. Environment configuration arrives
# from the operator-owned fprd.tfvars (PC-IAC-024); fprd.tfvars.example shows
# its shape. Subscription, location, ranges, and quota are the values the DR
# preflight (spec 009 T124) verifies from the live account.

variable "client" {
  type        = string
  description = "Client code of the governance prefix (MTS-IAC-101)."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "client must be 2-10 lowercase letters or digits."
  }
}

variable "project" {
  type        = string
  description = "Project code of the governance prefix (MTS-IAC-101)."

  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project))
    error_message = "project must be 2-15 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment code; the Azure recovery estate is fprd (MTS-IAC-101)."

  validation {
    condition     = var.environment == "fprd"
    error_message = "The Azure disaster-recovery root belongs to the fprd environment only."
  }
}

variable "subscription_id" {
  type        = string
  description = "Approved Azure subscription ID, verified by the DR preflight."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Approved Azure location by programmatic name, verified by the DR preflight."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "location must be a programmatic Azure location name."
  }
}

variable "vnet_cidr" {
  type        = string
  description = "VNet range selected by the DR preflight from live evidence."

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

variable "pod_cidr" {
  type        = string
  description = "Azure CNI Overlay pod range."

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be an IPv4 CIDR block."
  }
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service range."

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be an IPv4 CIDR block."
  }
}

variable "dns_service_ip" {
  type        = string
  description = "Cluster DNS service address inside the service range."

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0))
    error_message = "dns_service_ip must be an IPv4 address."
  }
}

variable "reserved_cidrs" {
  type        = list(string)
  description = "Every AWS VPC of the estate; no Azure range may overlap one (spec 009 FR-008)."

  validation {
    condition     = length(var.reserved_cidrs) > 0 && alltrue([for cidr in var.reserved_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Name every AWS VPC range as an IPv4 CIDR block; an empty list would let an Azure range collide with AWS."
  }
}

variable "api_server_authorized_cidrs" {
  type        = list(string)
  description = "The four approved operator /32 addresses for the API server and the Key Vault firewall (spec 009 FR-016)."

  validation {
    condition     = length(distinct(var.api_server_authorized_cidrs)) == 4 && length(var.api_server_authorized_cidrs) == 4 && alltrue([for cidr in var.api_server_authorized_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "The allowlist must be exactly the four approved operator addresses, each a /32 block; widening it is a separate reviewed change."
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

variable "system_node_pool" {
  type = object({
    vm_size   = string
    vcpus     = number
    min_count = number
    max_count = number
  })
  description = "System node pool VM size, its vCPU count, and the autoscaler bounds."

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.min_count <= var.system_node_pool.max_count
    error_message = "The autoscaler needs 1 <= min_count <= max_count."
  }
}

variable "regional_vcpu_quota" {
  type        = number
  description = "Regional vCPU quota for the node VM family, verified by the DR preflight."

  validation {
    condition     = var.regional_vcpu_quota > 0
    error_message = "The regional vCPU quota must be positive."
  }
}

variable "cluster_admin_principal_ids" {
  type        = set(string)
  description = "Entra object IDs of the operators granted cluster administration."

  validation {
    condition     = length(var.cluster_admin_principal_ids) > 0
    error_message = "Name at least one cluster administrator; local accounts are disabled."
  }
}

variable "enable_active_active" {
  type        = bool
  description = "Latency-based active-active routing. It stays false until a replicated data store exists (constitution principle 12, spec 009 FR-046)."
  default     = false

  validation {
    condition     = !var.enable_active_active
    error_message = "Active-active routing cannot be enabled: no replicated data store makes a user's requests consistent across clouds (constitution principle 12)."
  }
}
