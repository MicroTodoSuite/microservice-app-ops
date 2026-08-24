# Alphanumeric only: these values travel through JDBC URLs, HTTP basic-auth
# headers and Key Vault names, where quoting rules differ. 48 characters of
# base62 is well past the strength any of those consumers needs, so the entropy
# is bought with length instead of with characters that need escaping.
ephemeral "random_password" "generated" {
  for_each = var.names

  length  = 48
  special = false
}
