module "environment_jwt_values" {
  source = "../../../modules/environment-jwt-values"

  environments = var.shared_environments
}

# The full-profile Grafana and SonarQube credentials follow exactly the JWT
# pattern: generated here as ephemeral values, passed straight into write-only
# arguments, never written to plan or state. The set is empty until the owning
# foundation opts in, so the module holds its place without generating anything.
module "full_profile_secret_values" {
  source = "../../../modules/ephemeral-passwords"

  names = var.enable_full_profile_tooling_secrets ? [
    "grafana_admin",
    "sonarqube_db",
    "sonarqube_admin",
  ] : []
}
