variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region where the registry will be created"
  type        = string
}

variable "sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
}

variable "admin_enabled" {
  description = "Enable admin user for Azure Container Registry"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the registry"
  type        = map(string)
  default     = {}
}