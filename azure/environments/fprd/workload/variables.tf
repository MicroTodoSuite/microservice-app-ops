# Inputs of the fprd/workload Azure root. Environment configuration arrives
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

variable "pod_cidr" {
  type        = string
  description = "Azure CNI Overlay pod range selected by the DR preflight."

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be an IPv4 CIDR block."
  }
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service range selected by the DR preflight."

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
  description = "Every AWS VPC of the estate; the pod and service ranges must overlap none (spec 009 FR-008)."

  validation {
    condition     = length(var.reserved_cidrs) > 0 && alltrue([for cidr in var.reserved_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Name every AWS VPC range."
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
  description = "Regional vCPU quota of the node VM family, verified by the DR preflight."

  validation {
    condition     = var.regional_vcpu_quota > 0
    error_message = "The regional vCPU quota must be positive."
  }
}

variable "cluster_admin_group_object_ids" {
  type        = set(string)
  description = "Entra groups bound to cluster-admin; local accounts are disabled."

  validation {
    condition     = length(var.cluster_admin_group_object_ids) > 0
    error_message = "Name at least one Entra admin group."
  }
}
