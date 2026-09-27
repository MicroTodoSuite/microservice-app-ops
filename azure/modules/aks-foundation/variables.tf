# Inputs of the aks-foundation module. Names arrive built by the root
# (PC-IAC-025); ranges, subscription, and location are the values the DR
# preflight (spec 009 T124) verifies. Two CIDRs overlap exactly when their
# network addresses, truncated to the shorter prefix, are equal; the range
# validations below apply that test.

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
  description = "Environment code of the governance prefix; the Azure recovery estate is fprd (MTS-IAC-101)."

  validation {
    condition     = contains(["shd", "eco", "fdev", "fstg", "fprd"], var.environment)
    error_message = "environment must be one of shd, eco, fdev, fstg, or fprd."
  }
}

variable "subscription_id" {
  type        = string
  description = "Approved Azure subscription ID. The plan stops unless the authenticated client is in this subscription."

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Approved Azure location, by its programmatic name such as eastus2; every resource is created there."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "location must be a programmatic Azure location name, such as eastus2, never a display name."
  }
}

variable "names" {
  type = object({
    resource_group            = string
    ingress_resource_group    = string
    virtual_network           = string
    node_subnet               = string
    cluster                   = string
    cluster_identity          = string
    kubelet_identity          = string
    key_vault                 = string
    key_vault_reader_identity = string
    github_seed_identity      = string
    github_seed_role          = string
    container_registry        = string
    storage_account           = string
    ingress_public_ip         = string
  })
  description = "Physical names built in the root from the governance prefix (MTS-IAC-101, PC-IAC-025)."

  validation {
    condition = alltrue([
      for key, name in var.names :
      startswith(name, "${var.client}-${var.project}-${var.environment}-") && length(name) <= 28
      if !contains(["container_registry", "storage_account"], key)
    ])
    error_message = "Every standard name must start with <client>-<project>-<environment>- and be at most 28 characters (MTS-IAC-101)."
  }

  validation {
    condition     = startswith(var.names.container_registry, "${var.client}${var.project}${var.environment}") && can(regex("^[a-z0-9]{5,50}$", var.names.container_registry))
    error_message = "The registry name must be the separator-free prefix form, 5-50 lowercase letters or digits (MTS-IAC-101)."
  }

  validation {
    condition     = startswith(var.names.storage_account, "${var.client}${var.project}${var.environment}") && can(regex("^[a-z0-9]{3,24}$", var.names.storage_account))
    error_message = "The storage account name must be the separator-free prefix form, 3-24 lowercase letters or digits (MTS-IAC-101)."
  }

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]$", var.names.key_vault)) && !strcontains(var.names.key_vault, "--")
    error_message = "The Key Vault name must be 3-24 letters, digits, or single hyphens, starting with a letter."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes version: the 1.35 minor, optionally with a patch (spec 009 research decision 9)."

  validation {
    condition     = can(regex("^1\\.35(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "AKS must run Kubernetes 1.35."
  }
}

variable "reserved_cidrs" {
  type        = list(string)
  description = "Connected networks no Azure range may overlap: every AWS VPC of the estate (spec 009 FR-008)."

  validation {
    condition     = alltrue([for cidr in var.reserved_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every reserved range must be an IPv4 CIDR block."
  }
}

variable "vnet_cidr" {
  type        = string
  description = "VNet address space verified by the DR preflight."

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && alltrue([for reserved in var.reserved_cidrs : !(cidrhost(format("%s/%d", split("/", var.vnet_cidr)[0], min(tonumber(split("/", var.vnet_cidr)[1]), tonumber(split("/", reserved)[1]))), 0) == cidrhost(format("%s/%d", split("/", reserved)[0], min(tonumber(split("/", var.vnet_cidr)[1]), tonumber(split("/", reserved)[1]))), 0))])
    error_message = "The VNet range must be a CIDR block that overlaps no reserved network."
  }
}

variable "node_subnet_cidr" {
  type        = string
  description = "Private node subnet, inside the VNet range."

  validation {
    condition     = can(cidrhost(var.node_subnet_cidr, 0)) && tonumber(split("/", var.node_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) && cidrhost(format("%s/%d", split("/", var.node_subnet_cidr)[0], min(tonumber(split("/", var.node_subnet_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0) == cidrhost(format("%s/%d", split("/", var.vnet_cidr)[0], min(tonumber(split("/", var.node_subnet_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0)
    error_message = "The node subnet must be a CIDR block inside the VNet range."
  }
}

variable "pod_cidr" {
  type        = string
  description = "Azure CNI Overlay pod range; outside the VNet and every reserved network."

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0)) && !(cidrhost(format("%s/%d", split("/", var.pod_cidr)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0) == cidrhost(format("%s/%d", split("/", var.vnet_cidr)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0)) && alltrue([for reserved in var.reserved_cidrs : !(cidrhost(format("%s/%d", split("/", var.pod_cidr)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", reserved)[1]))), 0) == cidrhost(format("%s/%d", split("/", reserved)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", reserved)[1]))), 0))])
    error_message = "The pod range must overlap neither the VNet nor any reserved network."
  }
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service range; outside the VNet, the pod range, and every reserved network."

  validation {
    condition     = can(cidrhost(var.service_cidr, 0)) && !(cidrhost(format("%s/%d", split("/", var.service_cidr)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0) == cidrhost(format("%s/%d", split("/", var.vnet_cidr)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))), 0)) && !(cidrhost(format("%s/%d", split("/", var.service_cidr)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.pod_cidr)[1]))), 0) == cidrhost(format("%s/%d", split("/", var.pod_cidr)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.pod_cidr)[1]))), 0)) && alltrue([for reserved in var.reserved_cidrs : !(cidrhost(format("%s/%d", split("/", var.service_cidr)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", reserved)[1]))), 0) == cidrhost(format("%s/%d", split("/", reserved)[0], min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", reserved)[1]))), 0))])
    error_message = "The service range must overlap neither the VNet, the pod range, nor any reserved network."
  }
}

variable "dns_service_ip" {
  type        = string
  description = "Cluster DNS service address, inside the service range and not its network address."

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0)) && tonumber(split("/", "${var.dns_service_ip}/32")[1]) >= tonumber(split("/", var.service_cidr)[1]) && cidrhost(format("%s/%d", split("/", "${var.dns_service_ip}/32")[0], min(tonumber(split("/", "${var.dns_service_ip}/32")[1]), tonumber(split("/", var.service_cidr)[1]))), 0) == cidrhost(format("%s/%d", split("/", var.service_cidr)[0], min(tonumber(split("/", "${var.dns_service_ip}/32")[1]), tonumber(split("/", var.service_cidr)[1]))), 0) && var.dns_service_ip != cidrhost(var.service_cidr, 0)
    error_message = "The DNS service address must be inside the service range and must not be its network address."
  }
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "Operator addresses allowed to reach the public API server, each a /32 block (spec 009 FR-016)."

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0 && alltrue([for cidr in var.api_server_authorized_ip_ranges : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "The API server allowlist must name at least one address, and only /32 blocks; 0.0.0.0/0 and ranges are refused."
  }
}

variable "key_vault_allowed_cidrs" {
  type        = list(string)
  description = "Addresses allowed through the Key Vault firewall besides the node subnet, each a /32 block; the vault denies everything else."

  validation {
    condition     = alltrue([for cidr in var.key_vault_allowed_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "Key Vault firewall entries must be /32 blocks; 0.0.0.0/0 and ranges are refused."
  }
}

variable "system_node_pool" {
  type = object({
    vm_size   = string
    vcpus     = number
    min_count = number
    max_count = number
  })
  description = "Size and autoscaler bounds of the system node pool; vcpus is the vCPU count of vm_size, checked against the regional quota."

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.system_node_pool.vm_size)) && var.system_node_pool.vcpus > 0 && var.system_node_pool.min_count >= 1 && var.system_node_pool.min_count <= var.system_node_pool.max_count
    error_message = "The node pool needs an Azure VM size, a positive vCPU count, and 1 <= min_count <= max_count."
  }

  validation {
    condition     = var.system_node_pool.max_count * var.system_node_pool.vcpus <= var.regional_vcpu_quota
    error_message = "The autoscaler's maximum must fit the regional vCPU quota (MTS-IAC-104)."
  }
}

variable "regional_vcpu_quota" {
  type        = number
  description = "The subscription's regional vCPU quota for the node VM family, verified by the DR preflight."

  validation {
    condition     = var.regional_vcpu_quota > 0
    error_message = "The regional vCPU quota must be positive."
  }
}

variable "cluster_admin_principal_ids" {
  type        = set(string)
  description = "Entra object IDs granted Azure Kubernetes Service RBAC Cluster Admin on this cluster only; local accounts are disabled."

  validation {
    condition     = length(var.cluster_admin_principal_ids) > 0 && alltrue([for id in var.cluster_admin_principal_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "Name at least one cluster administrator by Entra object ID; with local accounts disabled, no one could reach the cluster otherwise."
  }
}

variable "key_vault_reader_service_accounts" {
  type = map(object({
    namespace = string
    name      = string
  }))
  description = "In-cluster service accounts, keyed by a stable label, that the reader identity trusts to read the vault."

  validation {
    condition     = length(var.key_vault_reader_service_accounts) > 0 && alltrue([for account in values(var.key_vault_reader_service_accounts) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", account.namespace)) && can(regex("^[a-z0-9]([-.a-z0-9]*[a-z0-9])?$", account.name))])
    error_message = "Name at least one service account, each by an exact Kubernetes namespace and name; wildcards are refused."
  }
}

variable "github_seed_subjects" {
  type        = set(string)
  description = "Exact GitHub Actions subjects, repo:<owner>/<repo>:environment:<environment>, that may seed the vault."

  validation {
    condition     = length(var.github_seed_subjects) > 0 && alltrue([for subject in var.github_seed_subjects : can(regex("^repo:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:environment:[A-Za-z0-9_.-]+$", subject))])
    error_message = "Each seed subject must pin an exact repository and environment, and at least one must exist."
  }
}

variable "ingress_dns_label" {
  type        = string
  description = "DNS label of the static ingress public IP; the provider FQDN is derived from it."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.ingress_dns_label))
    error_message = "The DNS label must be 3-63 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Transversal tags every resource carries (PC-IAC-004)."

  validation {
    condition     = length(setsubtract(["Client", "Project", "Environment", "Owner", "CostCenter", "ManagedBy", "Repository"], keys(var.common_tags))) == 0
    error_message = "common_tags must carry Client, Project, Environment, Owner, CostCenter, ManagedBy, and Repository."
  }
}

variable "additional_tags" {
  type        = map(string)
  description = "Extra tags merged into every resource's tags."
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.additional_tags) : length(key) > 0 && key != "Name"])
    error_message = "Additional tag keys must be non-empty and must not override Name."
  }
}
