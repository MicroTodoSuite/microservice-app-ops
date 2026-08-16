ephemeral "random_password" "environment_jwt" {
  for_each = var.environments

  length  = 64
  special = false
}
