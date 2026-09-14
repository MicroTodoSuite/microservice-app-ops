# Remote state in the shd/state bucket under fdev/workload/terraform.tfstate. The block is
# partial; the values come from workload.s3.tfbackend (PC-IAC-008).
terraform {
  backend "s3" {}
}
