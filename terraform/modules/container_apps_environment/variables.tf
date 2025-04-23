variable "name" {
  description = "Name of the Container Apps Environment"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region where the environment will be created"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for the Container Apps Environment"
  type        = string
  default     = null  # Hacerla opcional
}

variable "tags" {
  description = "Tags to apply to the Container Apps Environment"
  type        = map(string)
  default     = {}
}