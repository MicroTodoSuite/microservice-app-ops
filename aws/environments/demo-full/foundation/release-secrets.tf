module "environment_jwt_values" {
  source = "../../../modules/environment-jwt-values"
  count  = length(var.shared_environments) == 0 ? 0 : 1

  environments = var.shared_environments
}

locals {
  environment_jwt_values = length(module.environment_jwt_values) == 0 ? tomap({}) : module.environment_jwt_values[0].values
}
