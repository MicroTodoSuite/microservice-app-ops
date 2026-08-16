output "values" {
  description = "Independent write-only JWT values keyed by environment."
  value = {
    for environment, value in ephemeral.random_password.environment_jwt :
    environment => value.result
  }
  ephemeral = true
  sensitive = true
}
