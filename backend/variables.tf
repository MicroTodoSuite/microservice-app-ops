variable "location" {
  description = "Azure region donde crear el backend"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Nombre del grupo de recursos para el backend"
  type        = string
  default     = "tfstate-rg"
}

variable "subscription_id" {
  description = "ID de la suscripción de Azure"
  type        = string
}