# Plan-time tests of the fprd/workload root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias           = "principal"
  override_during = plan

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }

  mock_data "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0" }
  }

  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"] }
  }

  mock_data "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }

  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/lex-mts-fprd-role-cluster" }
  }

  mock_data "aws_kms_alias" {
    defaults = { target_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/lex-mts-fprd-eks-main"
      endpoint              = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-east-1.eks.amazonaws.com"
      platform_version      = "eks.1"
      certificate_authority = [{ data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" }] }]
    }
  }

  mock_resource "aws_eks_node_group" {
    defaults = { arn = "arn:aws:eks:us-east-1:123456789012:nodegroup/lex-mts-fprd-eks-main/lex-mts-fprd-ng-bootstrap/00000000-0000-0000-0000-000000000000" }
  }
}

# A mock provider cannot set computed attributes inside the cluster's vpc_config block, so the
# cluster security group ID it invents fails the node group module's sg- check. The node
# group module is replaced by its output here; its own tests cover its inputs.
override_module {
  target  = module.bootstrap_node_group
  outputs = { node_group_arn = "arn:aws:eks:us-east-1:123456789012:nodegroup/lex-mts-fprd-eks-main/lex-mts-fprd-ng-bootstrap/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = data.aws_iam_role.addon["vpccni"]
  values = { arn = "arn:aws:iam::123456789012:role/lex-mts-fprd-role-vpccni" }
}

override_data {
  target = data.aws_iam_role.addon["ebscsi"]
  values = { arn = "arn:aws:iam::123456789012:role/lex-mts-fprd-role-ebscsi" }
}

variables {
  client                       = "lex"
  project                      = "mts"
  environment                  = "fprd"
  aws_account_id               = "123456789012"
  aws_region                   = "us-east-1"
  deploy_role_arn              = "arn:aws:iam::123456789012:role/terraform-deploy"
  kubernetes_version           = "1.35"
  service_ipv4_cidr            = "172.20.0.0/16"
  endpoint_public_access_cidrs = []
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/terraform-deploy"]
  addon_versions = {
    vpc_cni            = "v1.23.0-eksbuild.1"
    kube_proxy         = "v1.35.3-eksbuild.18"
    coredns            = "v1.14.3-eksbuild.3"
    aws_ebs_csi_driver = "v1.64.0-eksbuild.1"
    pod_identity_agent = "v0.0.0-eksbuild.1"
  }
  node_release_version      = "1.35.6-20260818"
  node_instance_types       = ["m7i-flex.large"]
  node_scaling              = { min_size = 2, desired_size = 2, max_size = 4 }
  node_root_volume_size_gib = 50
}

run "builds_the_fprd_workload_names" {
  command = plan

  assert {
    condition     = local.cluster_name == "lex-mts-fprd-eks-main" && local.node_group_name == "lex-mts-fprd-ng-bootstrap" && local.launch_template_name == "lex-mts-fprd-lt-bootstrap" && local.control_plane_log_group.standard_name == "lex-mts-fprd-cwl-eks"
    error_message = "The root must build the fprd standard names (MTS-IAC-101)."
  }

  assert {
    condition     = local.cluster_security_group_name == "lex-mts-fprd-sg-cluster" && local.node_security_group_name == "lex-mts-fprd-sg-node" && local.addon_role_names == { vpccni = "lex-mts-fprd-role-vpccni", ebscsi = "lex-mts-fprd-role-ebscsi" }
    error_message = "The root must read fprd/security's groups and roles by the names that root gave them."
  }
}

run "protects_the_cluster_from_deletion_by_default" {
  command = plan

  assert {
    condition     = var.cluster_deletion_protection
    error_message = "The cluster must refuse deletion unless the lifecycle's unprotect bundle turns the protection off."
  }
}

run "gives_the_aws_addons_their_pod_identity_roles" {
  command = plan

  assert {
    condition     = local.addons["vpc-cni"].pod_identity_associations == { aws-node = "arn:aws:iam::123456789012:role/lex-mts-fprd-role-vpccni" } && local.addons["aws-ebs-csi-driver"].pod_identity_associations == { ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/lex-mts-fprd-role-ebscsi" }
    error_message = "The CNI and the EBS CSI controller must take their own Pod Identity roles."
  }

  assert {
    condition     = local.addons["eks-pod-identity-agent"].before_compute && local.addons["vpc-cni"].before_compute && local.addons["kube-proxy"].before_compute && !can(local.addons["coredns"].before_compute) && !can(local.addons["aws-ebs-csi-driver"].before_compute)
    error_message = "The agent, the CNI, and kube-proxy install with the cluster; CoreDNS and the EBS CSI driver wait for nodes."
  }

  assert {
    condition     = jsondecode(local.addons["vpc-cni"].configuration_values) == { enableNetworkPolicy = "true", env = { ENABLE_PREFIX_DELEGATION = "true" } }
    error_message = "The CNI must keep network policy enforcement and prefix delegation, as the legacy cluster ran it."
  }
}

run "grants_cluster_admin_only_to_the_named_principals" {
  command = plan

  assert {
    condition     = keys(local.access_entries) == ["arn:aws:iam::123456789012:role/terraform-deploy"] && local.access_entries["arn:aws:iam::123456789012:role/terraform-deploy"].policy_associations["cluster_admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    error_message = "Only the named principals may administer the cluster; the node role's entry is Amazon EKS's."
  }

  assert {
    condition     = !local.endpoint_public_access
    error_message = "Without operator addresses the API must stay private."
  }
}

run "opens_the_public_endpoint_only_to_named_operator_addresses" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["203.0.113.10/32"]
  }

  assert {
    condition     = local.endpoint_public_access
    error_message = "A named operator address must open the public endpoint."
  }
}

run "rejects_an_endpoint_open_to_the_internet" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "rejects_an_unpinned_addon_version" {
  command = plan

  variables {
    addon_versions = {
      vpc_cni            = "v1.23.0-eksbuild.1"
      kube_proxy         = "v1.35.3-eksbuild.18"
      coredns            = "v1.14.3-eksbuild.3"
      aws_ebs_csi_driver = "v1.64.0-eksbuild.1"
      pod_identity_agent = "<version from describe-addon-versions>"
    }
  }

  expect_failures = [var.addon_versions]
}

run "rejects_an_environment_other_than_fprd" {
  command = plan

  variables {
    environment = "fprd"
  }

  expect_failures = [var.environment]
}

run "rejects_a_network_with_a_single_private_subnet" {
  command = plan

  override_data {
    target = data.aws_subnets.private
    values = { ids = ["subnet-0123456789abcdef0"] }
  }

  expect_failures = [data.aws_subnets.private]
}
