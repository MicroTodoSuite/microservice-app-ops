# Plan-time tests of the eco/workload root against a mocked AWS provider (PC-IAC-018).
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
    defaults = { arn = "arn:aws:iam::123456789012:role/lex-mts-eco-role-cluster" }
  }

  mock_data "aws_kms_alias" {
    defaults = { target_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/lex-mts-eco-eks-main"
      endpoint              = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-east-1.eks.amazonaws.com"
      platform_version      = "eks.1"
      certificate_authority = [{ data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" }] }]
    }
  }

  mock_data "aws_route53_zone" {
    defaults = { zone_id = "Z08793112C5KLDBKRBY11" }
  }

  # No load balancer exists until the economical Ingresses reconcile.
  mock_data "aws_lbs" {
    defaults = { arns = [] }
  }

  mock_data "aws_lb" {
    defaults = {
      dns_name = "lex-mts-eco-alb-main-1234567890.us-east-1.elb.amazonaws.com"
      zone_id  = "Z35SXDOTRQ7X7K"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        { domain_name = "eco.microtodosuite.online", resource_record_name = "_0123.eco.microtodosuite.online.", resource_record_type = "CNAME", resource_record_value = "_4567.acm-validations.aws." },
        { domain_name = "*.eco.microtodosuite.online", resource_record_name = "_0123.eco.microtodosuite.online.", resource_record_type = "CNAME", resource_record_value = "_4567.acm-validations.aws." },
      ]
    }
  }

  mock_resource "aws_eks_node_group" {
    defaults = { arn = "arn:aws:eks:us-east-1:123456789012:nodegroup/lex-mts-eco-eks-main/lex-mts-eco-ng-bootstrap/00000000-0000-0000-0000-000000000000" }
  }
}

# A mock provider cannot set computed attributes inside the cluster's vpc_config block, so the
# cluster security group ID it invents fails the node group module's sg- check. The node
# group module is replaced by its output here; its own tests cover its inputs.
override_module {
  target  = module.bootstrap_node_group
  outputs = { node_group_arn = "arn:aws:eks:us-east-1:123456789012:nodegroup/lex-mts-eco-eks-main/lex-mts-eco-ng-bootstrap/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = data.aws_iam_role.addon["vpccni"]
  values = { arn = "arn:aws:iam::123456789012:role/lex-mts-eco-role-vpccni" }
}

override_data {
  target = data.aws_iam_role.addon["ebscsi"]
  values = { arn = "arn:aws:iam::123456789012:role/lex-mts-eco-role-ebscsi" }
}

variables {
  client                       = "lex"
  project                      = "mts"
  environment                  = "eco"
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
  public_zone_name          = "microtodosuite.online"
  ingress_host              = "eco.microtodosuite.online"
}

run "builds_the_eco_workload_names" {
  command = plan

  assert {
    condition     = local.cluster_name == "lex-mts-eco-eks-main" && local.node_group_name == "lex-mts-eco-ng-bootstrap" && local.launch_template_name == "lex-mts-eco-lt-bootstrap" && local.control_plane_log_group.standard_name == "lex-mts-eco-cwl-eks"
    error_message = "The root must build the eco standard names (MTS-IAC-101)."
  }

  assert {
    condition     = local.cluster_security_group_name == "lex-mts-eco-sg-cluster" && local.node_security_group_name == "lex-mts-eco-sg-node" && local.addon_role_names == { vpccni = "lex-mts-eco-role-vpccni", ebscsi = "lex-mts-eco-role-ebscsi" }
    error_message = "The root must read eco/security's groups and roles by the names that root gave them."
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
    condition     = local.addons["vpc-cni"].pod_identity_associations == { aws-node = "arn:aws:iam::123456789012:role/lex-mts-eco-role-vpccni" } && local.addons["aws-ebs-csi-driver"].pod_identity_associations == { ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/lex-mts-eco-role-ebscsi" }
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

run "names_the_economical_entry_point" {
  command = plan

  assert {
    condition     = local.ingress_certificate_domains == ["eco.microtodosuite.online", "*.eco.microtodosuite.online"]
    error_message = "One certificate must cover the production host and every environment's subdomain of it."
  }

  assert {
    condition     = local.ingress_group_name == "lex-mts-eco-alb-main" && local.ingress_load_balancer_tags == { "elbv2.k8s.aws/cluster" = "lex-mts-eco-eks-main", "ingress.k8s.aws/stack" = "lex-mts-eco-alb-main" }
    error_message = "The root must find exactly the shared load balancer the economical Ingresses create, by the tags the controller writes (MTS-IAC-101)."
  }
}

run "validates_the_certificate_with_its_single_shared_record" {
  command = apply

  assert {
    condition     = length(aws_route53_record.certificate_validation) == 1 && one(values(aws_route53_record.certificate_validation)).zone_id == "Z08793112C5KLDBKRBY11"
    error_message = "The host and its wildcard share one validation record, which must live in the canonical zone."
  }

  assert {
    condition     = aws_acm_certificate.ingress.validation_method == "DNS" && aws_acm_certificate.ingress.domain_name == "eco.microtodosuite.online" && aws_acm_certificate.ingress.subject_alternative_names == toset(["*.eco.microtodosuite.online"])
    error_message = "The certificate must be DNS-validated for the host and its wildcard."
  }
}

run "publishes_no_record_before_the_load_balancer_exists" {
  command = plan

  assert {
    condition     = length(aws_route53_record.ingress) == 0
    error_message = "Without the shared load balancer the root must plan no address record, so a first bring-up never fails on a missing target."
  }
}

run "publishes_the_host_and_its_subdomains_once_the_load_balancer_exists" {
  command = plan

  override_data {
    target = data.aws_lbs.ingress
    values = { arns = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/lex-mts-eco-alb-main/0123456789abcdef"] }
  }

  assert {
    condition     = toset(keys(aws_route53_record.ingress)) == toset(["eco.microtodosuite.online", "*.eco.microtodosuite.online"])
    error_message = "Once the load balancer exists, the host and its wildcard must both point at it."
  }

  assert {
    condition     = alltrue([for record in aws_route53_record.ingress : record.type == "A" && one(record.alias).name == "lex-mts-eco-alb-main-1234567890.us-east-1.elb.amazonaws.com" && one(record.alias).evaluate_target_health])
    error_message = "Each record must be an alias to the shared load balancer that follows its health."
  }
}

run "rejects_an_ingress_host_outside_the_public_zone" {
  command = plan

  variables {
    ingress_host = "eco.example.org"
  }

  expect_failures = [var.ingress_host]
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

run "rejects_an_environment_other_than_eco" {
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
