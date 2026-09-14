# Remote state in the shd/state bucket under fdev/security-irsa/terraform.tfstate. The block
# is partial; the values come from security-irsa.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
