output "values" {
  description = "Independent write-only JWT values keyed by environment."
  value = {
    for environment, value in ephemeral.aws_secretsmanager_random_password.environment_jwt :
    environment => value.random_password
  }
  ephemeral = true
  sensitive = true
}
