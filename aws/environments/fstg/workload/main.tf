# The fstg/workload root, third in the PC-IAC-022 order: the full-staging cluster, its managed
# add-ons, and the bootstrap node group. The roles, keys, security groups, and subnets
# come from fstg/security and fstg/networking.
module "eks_cluster" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//eks-cluster?ref=eks-cluster-v1.1.0"

  providers = {
    aws.project = aws.principal
  }

  client                       = var.client
  project                      = var.project
  environment                  = var.environment
  cluster_name                 = local.cluster_name
  kubernetes_version           = var.kubernetes_version
  cluster_role_arn             = data.aws_iam_role.cluster.arn
  subnet_ids                   = data.aws_subnets.private.ids
  security_group_ids           = [data.aws_security_group.cluster.id]
  endpoint_public_access       = local.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  service_ipv4_cidr            = var.service_ipv4_cidr
  secrets_kms_key_arn          = data.aws_kms_alias.secrets.target_key_arn
  control_plane_log_group      = local.control_plane_log_group
  access_entries               = local.access_entries
  addons                       = local.addons
  deletion_protection          = var.cluster_deletion_protection

  # CoreDNS and the EBS CSI driver wait for the bootstrap nodes.
  compute_ready = [module.bootstrap_node_group.node_group_arn]
}

# The nodes carry the cluster security group Amazon EKS creates, for control-plane traffic,
# and fstg/security's node group, for node-to-node traffic and egress.
module "bootstrap_node_group" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//eks-node-group?ref=eks-node-group-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client               = var.client
  project              = var.project
  environment          = var.environment
  cluster_name         = module.eks_cluster.cluster_name
  node_group_name      = local.node_group_name
  launch_template_name = local.launch_template_name
  node_role_arn        = data.aws_iam_role.node.arn
  subnet_ids           = data.aws_subnets.private.ids
  security_group_ids   = [module.eks_cluster.cluster_security_group_id, data.aws_security_group.node.id]
  kubernetes_version   = var.kubernetes_version
  release_version      = var.node_release_version
  ami_type             = "AL2023_x86_64_STANDARD"
  capacity_type        = "ON_DEMAND"
  instance_types       = var.node_instance_types
  scaling              = var.node_scaling
  root_volume          = { size_gib = var.node_root_volume_size_gib }
  labels               = local.node_labels
}
