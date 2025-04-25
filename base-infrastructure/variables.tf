# Provider variables
variable "subscription_id" {
  type        = string
  description = "The subscription ID to use for Azure resources."
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "microservice-app-rg"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Prod"
    Project     = "Microservice App"
  }
}

variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = "gacomicroserviceappacr"
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
}

variable "acr_admin_enabled" {
  description = "Enable admin user for Azure Container Registry"
  type        = bool
  default     = true
}

variable "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  type        = string
  default     = "microservice-env"
}

variable "jwt_secret" {
  description = "Secret key for JWT authentication"
  type        = string
  sensitive   = true
  default     = "PRFT"
}