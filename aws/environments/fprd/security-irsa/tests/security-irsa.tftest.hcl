# Plan-time tests of the fprd/security-irsa root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias           = "principal"
  override_during = plan

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }

  mock_data "aws_eks_cluster" {
    defaults = { identity = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" }] }] }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-other-AbCdEf" }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" }
  }
}

override_data {
  target = data.aws_secretsmanager_secret.jwt["dev"]
  values = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-jwtdev-AbCdEf" }
}

override_data {
  target = data.aws_secretsmanager_secret.webhook["secsecret"]
  values = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-slacksec-AbCdEf" }
}

variables {
  client                = "lex"
  project               = "mts"
  environment           = "fprd"
  aws_account_id        = "123456789012"
  aws_region            = "us-east-1"
  deploy_role_arn       = "arn:aws:iam::123456789012:role/terraform-deploy"
  jwt_reader_namespaces = { dev = "microtodo-dev", stg = "microtodo-staging" }
  service_image_keys    = ["frontend", "authapi"]
}

run "builds_the_irsa_names" {
  command = plan

  assert {
    condition     = local.oidc_provider_name == "lex-mts-fprd-oidc-eks" && local.irsa_role_names == { jwtdev = "lex-mts-fprd-role-jwtdev", jwtstg = "lex-mts-fprd-role-jwtstg", obssecret = "lex-mts-fprd-role-obssecret", secsecret = "lex-mts-fprd-role-secsecret", trivyecr = "lex-mts-fprd-role-trivyecr", kyvernoecr = "lex-mts-fprd-role-kyvernoecr" }
    error_message = "The root must build the spec 004 IRSA names, one role per application identity (MTS-IAC-101)."
  }

  assert {
    condition     = local.oidc_issuer_host == "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
    error_message = "IAM condition keys must name the issuer without its scheme."
  }
}

run "trusts_each_role_to_exactly_one_service_account" {
  command = plan

  assert {
    condition     = jsondecode(local.irsa_trust_policies["jwtdev"]).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" && jsondecode(local.irsa_trust_policies["jwtdev"]).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Only the cluster's OIDC provider may federate into an IRSA role."
  }

  assert {
    condition     = jsondecode(local.irsa_trust_policies["jwtdev"]).Statement[0].Condition.StringEquals == { "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:aud" = "sts.amazonaws.com", "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:sub" = "system:serviceaccount:microtodo-dev:external-secrets-jwt" }
    error_message = "The dev JWT reader must admit only microtodo-dev/external-secrets-jwt with the STS audience."
  }

  assert {
    condition     = local.irsa_roles["kyvernoecr"].subject == "system:serviceaccount:kyverno:kyverno-admission-controller" && local.irsa_roles["trivyecr"].subject == "system:serviceaccount:security:trivy-operator" && local.irsa_roles["obssecret"].subject == "system:serviceaccount:observability:observability-external-secrets-jwt" && local.irsa_roles["secsecret"].subject == "system:serviceaccount:security:security-external-secrets-jwt"
    error_message = "Each role must admit the service account its GitOps manifest annotates."
  }
}

run "grants_each_role_only_what_its_application_reads" {
  command = plan

  assert {
    condition     = jsondecode(local.irsa_roles["jwtdev"].policy).Statement[0].Resource == "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-jwtdev-AbCdEf" && toset(jsondecode(local.irsa_roles["jwtdev"].policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
    error_message = "A JWT reader may only describe and read its own environment's secret."
  }

  assert {
    condition     = jsondecode(local.irsa_roles["secsecret"].policy).Statement[0].Resource == "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-slacksec-AbCdEf"
    error_message = "The security reader may only read the Falcosidekick webhook."
  }

  assert {
    condition     = toset(jsondecode(local.irsa_roles["trivyecr"].policy).Statement[1].Action) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]) && jsondecode(local.irsa_roles["trivyecr"].policy).Statement[1].Resource == ["arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-authapi", "arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-frontend"]
    error_message = "Trivy Operator may only pull the shared service images."
  }

  assert {
    condition     = toset(jsondecode(local.irsa_roles["kyvernoecr"].policy).Statement[1].Action) == toset(["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]) && jsondecode(local.irsa_roles["kyvernoecr"].policy).Statement[0].Action == "ecr:GetAuthorizationToken"
    error_message = "Kyverno may only authenticate to ECR and read the shared service image artifacts."
  }
}

run "rejects_an_environment_other_than_fprd" {
  command = plan

  variables {
    environment = "eco"
  }

  expect_failures = [var.environment]
}

run "rejects_a_namespace_keyed_by_a_long_code" {
  command = plan

  variables {
    jwt_reader_namespaces = { staging = "microtodo-staging" }
  }

  expect_failures = [var.jwt_reader_namespaces]
}

run "rejects_an_image_key_that_breaks_the_naming_rule" {
  command = plan

  variables {
    service_image_keys = ["auth-api"]
  }

  expect_failures = [var.service_image_keys]
}
