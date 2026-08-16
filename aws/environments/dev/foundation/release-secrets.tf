module "environment_jwt_values" {
  source = "../../../modules/environment-jwt-values"

  environments = var.shared_environments
}
