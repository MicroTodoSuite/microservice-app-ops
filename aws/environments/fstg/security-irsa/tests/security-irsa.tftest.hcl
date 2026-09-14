# Plan-time tests of the fstg/security-irsa root against a mocked AWS provider (PC-IAC-018).
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
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fstg-sm-other-AbCdEf" }
  }

  mock_data "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:lex-mts-fstg-sqs-karpenter"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/lex-mts-fstg-sqs-karpenter"
    }
  }

  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/lex-mts-fstg-role-node" }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" }
  }
}

override_data {
  target = data.aws_secretsmanager_secret.jwt["dev"]
  values = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fstg-sm-jwtdev-AbCdEf" }
}

override_data {
  target = data.aws_secretsmanager_secret.webhook["secsecret"]
  values = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fstg-sm-slacksec-AbCdEf" }
}

variables {
  client                = "lex"
  project               = "mts"
  environment           = "fstg"
  aws_account_id        = "123456789012"
  aws_region            = "us-east-1"
  deploy_role_arn       = "arn:aws:iam::123456789012:role/terraform-deploy"
  jwt_reader_namespaces = { dev = "microtodo-dev", stg = "microtodo-staging" }
  service_image_keys    = ["frontend", "authapi"]
}

run "builds_the_irsa_names" {
  command = plan

  assert {
    condition     = local.oidc_provider_name == "lex-mts-fstg-oidc-eks" && local.irsa_role_names == { jwtdev = "lex-mts-fstg-role-jwtdev", jwtstg = "lex-mts-fstg-role-jwtstg", obssecret = "lex-mts-fstg-role-obssecret", secsecret = "lex-mts-fstg-role-secsecret", trivyecr = "lex-mts-fstg-role-trivyecr", kyvernoecr = "lex-mts-fstg-role-kyvernoecr", karpenter = "lex-mts-fstg-role-karpenter", lbcontrol = "lex-mts-fstg-role-lbcontrol" }
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
    condition     = jsondecode(local.irsa_roles["jwtdev"].policy).Statement[0].Resource == "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fstg-sm-jwtdev-AbCdEf" && toset(jsondecode(local.irsa_roles["jwtdev"].policy).Statement[0].Action) == toset(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
    error_message = "A JWT reader may only describe and read its own environment's secret."
  }

  assert {
    condition     = jsondecode(local.irsa_roles["secsecret"].policy).Statement[0].Resource == "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fstg-sm-slacksec-AbCdEf"
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

run "gives_the_karpenter_controller_its_reference_permissions" {
  command = plan

  assert {
    condition     = local.irsa_roles["karpenter"].subject == "system:serviceaccount:kube-system:karpenter"
    error_message = "The controller role must admit only kube-system/karpenter, the service account the vendored release creates."
  }

  assert {
    condition     = [for statement in jsondecode(local.irsa_roles["karpenter"].policy).Statement : statement.Sid] == ["AllowScopedEC2InstanceAccessActions", "AllowScopedEC2LaunchTemplateAccessActions", "AllowScopedEC2InstanceActionsWithTags", "AllowScopedResourceCreationTagging", "AllowScopedResourceTagging", "AllowScopedDeletion", "AllowPassingInstanceRole", "AllowScopedInstanceProfileCreationActions", "AllowScopedInstanceProfileTagActions", "AllowScopedInstanceProfileActions", "AllowAPIServerEndpointDiscovery", "AllowInterruptionQueueActions", "AllowZonalShiftStatusReadOnly", "AllowRegionalReadActions", "AllowSSMReadActions", "AllowPricingReadActions", "AllowUnscopedInstanceProfileListAction", "AllowInstanceProfileReadActions"]
    error_message = "The controller policy must carry the eighteen statements of Karpenter's reference template, under its own statement identifiers."
  }

  assert {
    condition     = one([for statement in jsondecode(local.irsa_roles["karpenter"].policy).Statement : statement if statement.Sid == "AllowInterruptionQueueActions"]).Resource == "arn:aws:sqs:us-east-1:123456789012:lex-mts-fstg-sqs-karpenter" && one([for statement in jsondecode(local.irsa_roles["karpenter"].policy).Statement : statement if statement.Sid == "AllowPassingInstanceRole"]).Resource == "arn:aws:iam::123456789012:role/lex-mts-fstg-role-node"
    error_message = "The controller may poll only this environment's interruption queue and pass only its node role to the instance profiles it generates."
  }

  assert {
    condition     = one([for statement in jsondecode(local.irsa_roles["karpenter"].policy).Statement : statement if statement.Sid == "AllowScopedDeletion"]).Condition.StringEquals == { "aws:ResourceTag/kubernetes.io/cluster/lex-mts-fstg-eks-main" = "owned" } && one([for statement in jsondecode(local.irsa_roles["karpenter"].policy).Statement : statement if statement.Sid == "AllowAPIServerEndpointDiscovery"]).Resource == "arn:aws:eks:us-east-1:123456789012:cluster/lex-mts-fstg-eks-main"
    error_message = "Every scoped statement must be confined to this cluster: Karpenter may terminate only the instances this cluster owns and describe only this cluster."
  }

  assert {
    condition     = length(local.irsa_roles["karpenter"].policy) <= 10240
    error_message = "IAM allows a role at most 10240 characters of inline policy."
  }
}

run "gives_the_load_balancer_controller_the_upstream_permissions_for_its_cluster_only" {
  command = plan

  assert {
    condition     = local.irsa_roles["lbcontrol"].subject == "system:serviceaccount:kube-system:aws-load-balancer-controller"
    error_message = "The controller role must admit only kube-system/aws-load-balancer-controller, the service account the vendored release creates."
  }

  assert {
    condition     = [for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement.Sid] == ["CreateElasticLoadBalancingServiceLinkedRole", "DescribeNetworkAndLoadBalancers", "UseCertificatesFirewallsAndShield", "ManageIngressOnSecurityGroups", "CreateSecurityGroups", "TagSecurityGroupsOnCreation", "RetagClusterSecurityGroups", "ManageClusterSecurityGroups", "CreateClusterLoadBalancersAndTargetGroups", "ManageListenersAndRules", "RetagClusterLoadBalancersAndTargetGroups", "TagListenersAndRules", "ManageClusterLoadBalancersAndTargetGroups", "TagLoadBalancersAndTargetGroupsOnCreation", "RegisterTargets", "ModifyListenersRulesAndWebAcls"]
    error_message = "The controller policy must carry the sixteen statements of the upstream v3.5.0 IAM policy, each under its own statement identifier."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : lookup(try(statement.Condition.Null, {}), "aws:ResourceTag/elbv2.k8s.aws/cluster", "unset") != "false" && lookup(try(statement.Condition.Null, {}), "aws:RequestTag/elbv2.k8s.aws/cluster", "unset") != "false"])
    error_message = "No statement may accept any cluster's tag: every cluster-tag condition must name this cluster."
  }

  assert {
    condition     = one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "ManageClusterLoadBalancersAndTargetGroups"]).Condition == { StringEquals = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "lex-mts-fstg-eks-main" } } && contains(one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "ManageClusterLoadBalancersAndTargetGroups"]).Action, "elasticloadbalancing:DeleteLoadBalancer")
    error_message = "The controller may delete or modify only the load balancers and target groups this cluster tagged."
  }

  assert {
    condition     = one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "CreateClusterLoadBalancersAndTargetGroups"]).Condition == { StringEquals = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "lex-mts-fstg-eks-main" } } && one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "RetagClusterSecurityGroups"]).Condition == { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "true" }, StringEquals = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "lex-mts-fstg-eks-main" } }
    error_message = "The controller may create only load balancers tagged for this cluster, and may retag only this cluster's security groups without moving them to another cluster."
  }

  assert {
    condition     = one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "TagSecurityGroupsOnCreation"]).Resource == "arn:aws:ec2:us-east-1:123456789012:security-group/*" && one([for statement in jsondecode(local.irsa_roles["lbcontrol"].policy).Statement : statement if statement.Sid == "RegisterTargets"]).Resource == "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/*/*"
    error_message = "Resource ARNs must name this environment's partition, Region, and account instead of wildcards."
  }

  assert {
    condition     = length(local.irsa_roles["lbcontrol"].policy) <= 10240
    error_message = "IAM allows a role at most 10240 characters of inline policy."
  }
}

run "rejects_an_environment_other_than_fstg" {
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
