# The one root that keeps local state (PC-IAC-008 adaptation): it creates the bucket and
# key that every other root's backend uses, so it cannot store its own state there
# before they exist. The state file is gitignored and backed up under
# ~/backups-microtodosuite/ before every apply.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
