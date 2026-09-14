# Remote state in the shd/state bucket under fprd/security/terraform.tfstate. The block is
# partial; the values come from security.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
