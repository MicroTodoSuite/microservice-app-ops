# Remote state in the shd/state bucket under shd/dns/terraform.tfstate. The block is
# partial; the values come from dns.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
