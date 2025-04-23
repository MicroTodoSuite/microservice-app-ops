resource "azurerm_container_app" "app" {
  name                         = var.container_app_name
  container_app_environment_id = data.azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  template {
    container {
      name   = "${var.container_app_name}-container"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = { for k, v in var.environment_variables : k => v if !startswith(v, "secretref:") }
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = { for k, v in var.environment_variables : k => trimprefix(v, "secretref:") if startswith(v, "secretref:") }
        content {
          name        = env.key
          secret_name = env.value
        }
      }
      command = length(var.command) > 0 ? var.command : null
      args    = length(var.args) > 0 ? var.args : null
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  }

  # Only set ingress if needed
  dynamic "ingress" {
    for_each = var.ingress_target_port > 0 ? [1] : []
    content {
      external_enabled = var.ingress_external
      target_port      = var.ingress_target_port
      transport        = var.is_tcp ? "tcp" : "auto"

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  dynamic "secret" {
    for_each = var.secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  registry {
    server               = var.registry_server
    username             = var.registry_username
    password_secret_name = "registry-password"
  }

  secret {
    name  = "registry-password"
    value = var.registry_password
  }
}

data "azurerm_container_app_environment" "env" {
  name                = var.container_apps_environment
  resource_group_name = var.resource_group_name
}