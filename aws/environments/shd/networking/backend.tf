# Remote state in the shd/state bucket under shd/networking/terraform.tfstate. The
# block is partial; the values come from networking.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
