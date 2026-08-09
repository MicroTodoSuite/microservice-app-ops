module "state_backend" {
  source = "../../../modules/state-backend"

  project             = "microtodosuite"
  environment         = "dev"
  expected_account_id = var.expected_account_id
  aws_region          = var.aws_region
  owner               = var.owner
  common_tags         = var.common_tags

  depends_on = [terraform_data.account_guard]
}
