# Full-profile dev environment.
#
# A spoke of the shared egress hub, in its own VPC, its own EKS cluster, and its
# own state key. It creates no shared resource: the account-level singletons
# (GitHub OIDC provider, shared ECR, JWT secret containers) are owned by
# aws/environments/dev/foundation, and this root only reads the one secret its
# own environment needs.

module "foundation" {
  source = "../../../modules/environment-foundation"

  environment         = var.environment
  expected_account_id = var.expected_account_id
  aws_region          = var.aws_region
  owner               = var.owner
  common_tags         = var.common_tags

  availability_zones             = var.availability_zones
  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidrs            = var.public_subnet_cidrs
  private_subnet_cidrs           = var.private_subnet_cidrs
  single_nat_gateway             = var.single_nat_gateway
  cluster_public_access_cidrs    = var.cluster_public_access_cidrs
  bootstrap_admin_principal_arns = var.bootstrap_admin_principal_arns

  # No NAT gateway and no Elastic IP of its own; private workers default-route
  # to the shared transit gateway instead.
  outbound_mode      = var.outbound_mode
  transit_gateway_id = var.transit_gateway_id

  bootstrap_node_instance_types      = var.bootstrap_node_instance_types
  bootstrap_node_ami_release_version = var.bootstrap_node_ami_release_version
  bootstrap_node_min_size            = var.bootstrap_node_min_size
  bootstrap_node_desired_size        = var.bootstrap_node_desired_size
  bootstrap_node_max_size            = var.bootstrap_node_max_size
  bootstrap_node_volume_size         = var.bootstrap_node_volume_size
  iam_permissions_boundary_arn       = var.iam_permissions_boundary_arn

  create_shared_resources         = var.create_shared_resources
  shared_environments             = var.shared_environments
  neutral_service_names           = var.neutral_service_names
  github_oidc_subjects            = var.github_oidc_subjects
  environment_jwt_secret_version  = var.environment_jwt_secret_version
  environment_jwt_values          = {}
  kyverno_service_account_subject = var.kyverno_service_account_subject

  # Exactly one reader, named for this cluster, scoped to this one environment's
  # secret.
  consumer_jwt_environment = var.consumer_jwt_environment

  enable_full_profile_cluster_prerequisites = var.enable_full_profile_cluster_prerequisites
  aws_load_balancer_controller_policy_arns  = var.aws_load_balancer_controller_policy_arns
}
