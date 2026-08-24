output "values" {
  description = "Independent write-only values keyed by name."
  value = {
    for name, password in ephemeral.random_password.generated :
    name => password.result
  }
  ephemeral = true
  sensitive = true
}
