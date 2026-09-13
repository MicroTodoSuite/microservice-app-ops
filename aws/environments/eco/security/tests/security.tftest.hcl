# Plan-time tests of the eco/security root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias           = "principal"
  override_during = plan

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }

  mock_data "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }
}

variables {
  client                = "lex"
  project               = "mts"
  environment           = "eco"
  aws_account_id        = "123456789012"
  aws_region            = "us-east-1"
  deploy_role_arn       = "arn:aws:iam::123456789012:role/terraform-deploy"
  jwt_environment_codes = ["dev", "stg", "prd", "dmo"]
}

run "builds_the_eco_security_names" {
  command = plan

  assert {
    condition     = local.cluster_role_name == "lex-mts-eco-role-cluster" && local.node_role_name == "lex-mts-eco-role-node" && local.secrets_key_name == "lex-mts-eco-kms-eks" && local.logs_key_name == "lex-mts-eco-kms-ekslogs"
    error_message = "The root must build the eco standard names (MTS-IAC-101)."
  }

  assert {
    condition     = local.jwt_secret_names == { dev = "lex-mts-eco-sm-jwtdev", stg = "lex-mts-eco-sm-jwtstg", prd = "lex-mts-eco-sm-jwtprd", dmo = "lex-mts-eco-sm-jwtdmo" } && local.webhook_secrets["slacksec"].name == "lex-mts-eco-sm-slacksec"
    error_message = "Every secret must carry its spec 004 name."
  }
}

run "grants_each_role_only_its_documented_trust_and_policies" {
  command = plan

  assert {
    condition     = jsondecode(local.cluster_trust_policy).Statement[0].Principal.Service == "eks.amazonaws.com" && jsondecode(local.node_trust_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "Only the EKS control plane may assume the cluster role, and only EC2 the node role."
  }

  assert {
    condition     = toset(local.node_managed_policy_arns) == toset(["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly", "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"])
    error_message = "The node role gets the worker policy and pull-only ECR; the CNI policy belongs to the vpc-cni role."
  }

  assert {
    condition     = jsondecode(local.cluster_policies["use-the-secrets-key"]).Statement[0].Resource == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "The cluster role may use only the secrets key."
  }
}

run "limits_the_logs_key_to_the_control_plane_log_group" {
  command = plan

  assert {
    condition     = jsondecode(local.logs_key_policy).Statement[1].Principal.Service == "logs.us-east-1.amazonaws.com" && jsondecode(local.logs_key_policy).Statement[1].Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/eks/lex-mts-eco-eks-main/cluster"
    error_message = "CloudWatch Logs may use the logs key only for the cluster's control-plane log group."
  }
}

run "keeps_the_legacy_node_and_cluster_rules" {
  command = plan

  assert {
    condition     = toset(keys(local.node_ingress_rules)) == toset(["cluster-443", "cluster-4443", "cluster-6443", "cluster-8443", "cluster-9443", "cluster-10250", "cluster-10251", "self-dns-tcp", "self-dns-udp", "self-ephemeral-tcp"])
    error_message = "The node group must keep exactly the ingress the legacy module gave it."
  }

  assert {
    condition     = keys(local.cluster_ingress_rules) == ["nodes-https"] && local.cluster_ingress_rules["nodes-https"].from_port == 443
    error_message = "The extra cluster group admits only the nodes, on 443."
  }

  assert {
    condition     = local.node_egress_rules["all"].cidr_ipv4 == "0.0.0.0/0" && local.node_egress_rules["all"].ip_protocol == "-1"
    error_message = "The node group keeps the recorded AWS-0104 egress exception, no wider and no narrower."
  }
}

run "rejects_an_environment_other_than_eco" {
  command = plan

  variables {
    environment = "shd"
  }

  expect_failures = [var.environment]
}

run "rejects_a_repeated_environment_code" {
  command = plan

  variables {
    jwt_environment_codes = ["dev", "dev"]
  }

  expect_failures = [var.jwt_environment_codes]
}
