ephemeral "aws_secretsmanager_random_password" "environment_jwt" {
  for_each = var.shared_environments

  password_length            = 64
  exclude_punctuation        = true
  include_space              = false
  require_each_included_type = true
}
