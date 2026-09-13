# The shd/state root: the S3 bucket and KMS key that hold every other root's state, each
# under the key <environment>/<domain>/terraform.tfstate (PC-IAC-008). The module keeps
# them with prevent_destroy.
module "state_backend" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//state-backend?ref=state-backend-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client       = var.client
  project      = var.project
  environment  = var.environment
  bucket_name  = local.state_bucket_name
  kms_key_name = local.state_key_name
}
