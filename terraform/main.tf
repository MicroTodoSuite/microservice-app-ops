# Configure the Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Resource Group Module
module "resource_group" {
  source   = "./modules/resource_group"
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Container Registry Module
module "container_registry" {
  source              = "./modules/container_registry"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  acr_name            = var.acr_name
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled
  tags                = var.tags
  depends_on          = [module.resource_group]
}

# Container Apps Environment Module
module "container_apps_environment" {
  source              = "./modules/container_apps_environment"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = var.container_apps_environment_name
  tags       = var.tags
  depends_on = [module.resource_group]
}

# Container Apps Modules
module "zipkin" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "zipkin"
  container_apps_environment = module.container_apps_environment.name
  image                      = "openzipkin/zipkin:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = true
  ingress_target_port        = 9411
  environment_variables      = {}
  secrets                    = {}
  tags                       = var.tags
  depends_on                 = [module.container_apps_environment]
}

module "redis" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "redis"
  container_apps_environment = module.container_apps_environment.name
  image                      = "redis:7.0-alpine"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 2.0
  memory                     = "4Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 6379
  is_tcp                     = true
  environment_variables      = {}
  secrets                    = {}
  tags                       = var.tags
  depends_on                 = [module.container_apps_environment]
}

module "users_api" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "users-api"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/users-api:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 8083
  environment_variables = {
    "JWT_SECRET"             = "secretref:jwt-secret"
    "SERVER_PORT"            = "8083"
    "SPRING_PROFILES_ACTIVE" = "default"
    "ZIPKIN_URL"             = "http://zipkin/"
  }

  secrets = {
    "jwt-secret" = var.jwt_secret
  }
  tags       = var.tags
  depends_on = [module.container_apps_environment, module.redis, module.zipkin]
}

module "auth_api" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "auth-api"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/auth-api:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 8000
  environment_variables = {
    "JWT_SECRET"        = "secretref:jwt-secret"
    "AUTH_API_PORT"     = "8000"
    "USERS_API_ADDRESS" = "http://users-api"
    "ZIPKIN_URL"        = "http://zipkin/api/v2/spans"
  }
  secrets = {
    "jwt-secret" = var.jwt_secret
  }
  tags       = var.tags
  depends_on = [module.container_apps_environment, module.redis, module.users_api]
}

module "todos_api" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "todos-api"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/todos-api:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 8082
  environment_variables = {
    "TODO_API_PORT" = "8082"
    "REDIS_HOST"    = "redis"
    "REDIS_PORT"    = "6379"
    "REDIS_CHANNEL" = "log_channel"
    "USERS_API_URL" = "http://users-api"
    "ZIPKIN_URL"    = "http://zipkin/api/v2/spans"
    "JWT_SECRET"    = "secretref:jwt-secret"
  }
  secrets = {
    "jwt-secret" = var.jwt_secret
  }
  tags       = var.tags
  depends_on = [module.container_apps_environment, module.redis, module.users_api]
}

module "log_message_processor" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "log-message-processor"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/log-message-processor:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 2.0
  memory                     = "4Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 8081
  environment_variables = {
    "PORT"          = "8081"
    "REDIS_HOST"    = "redis"
    "REDIS_PORT"    = "6379"
    "REDIS_CHANNEL" = "log_channel"
    "ZIPKIN_URL"    = "http://zipkin/api/v2/spans"
  }
  secrets    = {}
  tags       = var.tags
  depends_on = [module.container_apps_environment, module.redis]
}

module "frontend" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "frontend"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/frontend:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = true
  ingress_target_port        = 8080
  environment_variables = {
    "PORT"              = "8080"
    "AUTH_API_ADDRESS"  = "http://auth-api"
    "TODOS_API_ADDRESS" = "http://todos-api"
    "ZIPKIN_URL"        = "http://zipkin/api/v2/spans"
    "JWT_SECRET"        = "secretref:jwt-secret"
  }
  secrets = {
    "jwt-secret" = var.jwt_secret
  }
  tags       = var.tags
  depends_on = [module.container_apps_environment, module.auth_api, module.todos_api, module.users_api]
}

module "frontend_exporter" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "frontend-exporter"
  container_apps_environment = module.container_apps_environment.name
  image                      = "nginx/nginx-prometheus-exporter:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 3
  ingress_external           = false
  ingress_target_port        = 9113
  environment_variables      = {}
  secrets                    = {}
  command                    = ["/usr/bin/nginx-prometheus-exporter"]
  args                       = ["--nginx.scrape-uri=http://frontend/nginx_status"]
  tags                       = var.tags
  depends_on                 = [module.container_apps_environment, module.frontend]
}

module "prometheus" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "prometheus"
  container_apps_environment = module.container_apps_environment.name
  image                      = "${module.container_registry.login_server}/prometheus:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 1
  ingress_external           = true
  ingress_target_port        = 9090
  environment_variables = {
    "AUTH_API_TARGET"          = "auth-api"
    "USERS_API_TARGET"         = "users-api"
    "TODOS_API_TARGET"         = "todos-api"
    "LOG_PROCESSOR_TARGET"     = "log-message-processor"
    "FRONTEND_EXPORTER_TARGET" = "frontend-exporter"
  }
  depends_on = [module.container_apps_environment, module.auth_api, module.users_api, module.todos_api, module.log_message_processor, module.frontend]
  tags       = var.tags
}

module "grafana" {
  source                     = "./modules/container_apps"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  container_app_name         = "grafana"
  container_apps_environment = module.container_apps_environment.name
  image                      = "grafana/grafana:latest"
  registry_server            = module.container_registry.login_server
  registry_username          = module.container_registry.admin_username
  registry_password          = module.container_registry.admin_password
  cpu                        = 1.0
  memory                     = "2Gi"
  min_replicas               = 1
  max_replicas               = 1
  ingress_external           = true
  ingress_target_port        = 3000
  environment_variables = {
    "GF_SECURITY_ADMIN_PASSWORD" = "12345",
    "GF_PATHS_PROVISIONING"      = "/etc/grafana/provisioning"
  }
  depends_on = [module.container_apps_environment, module.prometheus]
  tags       = var.tags
}