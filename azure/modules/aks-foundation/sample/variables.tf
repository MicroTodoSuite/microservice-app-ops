# Inputs of the sample; see ../README.md for their meaning.

variable "client" {
  type        = string
  description = "Client code."
}

variable "project" {
  type        = string
  description = "Project code."
}

variable "environment" {
  type        = string
  description = "Environment code."
}

variable "subscription_id" {
  type        = string
  description = "Approved Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Programmatic Azure location name."
}

variable "network" {
  type = object({
    vnet_cidr        = string
    node_subnet_cidr = string
    pod_cidr         = string
    service_cidr     = string
    dns_service_ip   = string
    reserved_cidrs   = list(string)
  })
  description = "Verified network ranges and the connected networks they must avoid."
}

variable "operator_cidrs" {
  type        = list(string)
  description = "Operator /32 addresses for the API server and the Key Vault firewall."
}

variable "system_node_pool" {
  type = object({
    vm_size   = string
    vcpus     = number
    min_count = number
    max_count = number
  })
  description = "System node pool size and autoscaler bounds."
}

variable "regional_vcpu_quota" {
  type        = number
  description = "Regional vCPU quota."
}

variable "cluster_admin_principal_ids" {
  type        = set(string)
  description = "Entra object IDs granted cluster administration."
}

variable "github_seed_subjects" {
  type        = set(string)
  description = "Exact GitHub subjects allowed to seed the vault."
}
