module "foundation" {
  source = "../../../modules/environment-foundation"

  expected_account_id = var.expected_account_id
  aws_region          = var.aws_region
  owner               = var.owner
  common_tags         = var.common_tags

  availability_zones             = var.availability_zones
  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidrs            = var.public_subnet_cidrs
  private_subnet_cidrs           = var.private_subnet_cidrs
  cluster_public_access_cidrs    = var.cluster_public_access_cidrs
  bootstrap_admin_principal_arns = var.bootstrap_admin_principal_arns

  bootstrap_node_instance_types = var.bootstrap_node_instance_types
  bootstrap_node_min_size       = var.bootstrap_node_min_size
  bootstrap_node_desired_size   = var.bootstrap_node_desired_size
  bootstrap_node_max_size       = var.bootstrap_node_max_size
  bootstrap_node_volume_size    = var.bootstrap_node_volume_size
  iam_permissions_boundary_arn  = var.iam_permissions_boundary_arn
}
