variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region where the container app will be created"
  type        = string
}

variable "container_app_name" {
  description = "Name of the container app"
  type        = string
}

variable "container_apps_environment" {
  description = "Name of the Container Apps Environment"
  type        = string
}

variable "image" {
  description = "Container image to deploy"
  type        = string
}

variable "registry_server" {
  description = "Container registry server"
  type        = string
}

variable "registry_username" {
  description = "Container registry username"
  type        = string
}

variable "registry_password" {
  description = "Container registry password"
  type        = string
  sensitive   = true
}

variable "cpu" {
  description = "CPU cores allocated to the container"
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory allocated to the container"
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 3
}

variable "ingress_external" {
  description = "Enable external ingress"
  type        = bool
  default     = false
}

variable "ingress_target_port" {
  description = "Target port for ingress"
  type        = number
  default     = 0
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "command" {
  description = "Command override for the container"
  type        = list(string)
  default     = []
}

variable "is_tcp" {
  description = "Is the container TCP?"
  type        = bool
  default     = false
}

variable "args" {
  description = "Arguments for the container"
  type        = list(string)
  default     = []
}

variable "secrets" {
  description = "Secrets for the container"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to the container app"
  type        = map(string)
  default     = {}
}