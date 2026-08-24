module "foundation" {
  source = "../../../modules/environment-foundation"

  environment             = var.environment
  expected_account_id     = var.expected_account_id
  aws_region              = var.aws_region
  public_hosted_zone_name = var.public_hosted_zone_name
  owner                   = var.owner
  common_tags             = var.common_tags

  availability_zones             = var.availability_zones
  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidrs            = var.public_subnet_cidrs
  private_subnet_cidrs           = var.private_subnet_cidrs
  single_nat_gateway             = var.single_nat_gateway
  cluster_public_access_cidrs    = var.cluster_public_access_cidrs
  bootstrap_admin_principal_arns = var.bootstrap_admin_principal_arns

  bootstrap_node_instance_types      = var.bootstrap_node_instance_types
  bootstrap_node_ami_release_version = var.bootstrap_node_ami_release_version
  bootstrap_node_min_size            = var.bootstrap_node_min_size
  bootstrap_node_desired_size        = var.bootstrap_node_desired_size
  bootstrap_node_max_size            = var.bootstrap_node_max_size
  bootstrap_node_volume_size         = var.bootstrap_node_volume_size
  iam_permissions_boundary_arn       = var.iam_permissions_boundary_arn
  create_shared_resources            = var.create_shared_resources

  shared_environments             = var.shared_environments
  neutral_service_names           = var.neutral_service_names
  github_oidc_subjects            = var.github_oidc_subjects
  environment_jwt_secret_version  = var.environment_jwt_secret_version
  environment_jwt_values          = module.environment_jwt_values.values
  kyverno_service_account_subject = var.kyverno_service_account_subject

  observability_service_account_subject = var.observability_service_account_subject
  security_service_account_subject      = var.security_service_account_subject
}
