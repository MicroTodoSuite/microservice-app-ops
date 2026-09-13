# Remote state in the shd/state bucket under shd/registry/terraform.tfstate. The block is
# partial; the values come from registry.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
