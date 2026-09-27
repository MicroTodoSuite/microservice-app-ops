# Plan-time tests of the shd/security root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias           = "principal"
  override_during = plan

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }

  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }

  mock_data "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::lex-mts-shd-s3-tfstate-123456789012" }
  }
}

variables {
  client                       = "lex"
  project                      = "mts"
  environment                  = "shd"
  aws_account_id               = "123456789012"
  aws_region                   = "us-east-1"
  deploy_role_arn              = "arn:aws:iam::123456789012:role/terraform-deploy"
  github_organization          = "MicroTodoSuite"
  image_publisher_repositories = ["microservice-app-frontend", "microservice-app-auth-api"]
  service_image_keys           = ["frontend", "authapi"]
  deploy_role_operator_arns    = ["arn:aws:iam::123456789012:user/operator-b", "arn:aws:iam::123456789012:user/operator-a"]
  adopt_existing_github_oidc   = false
  dr_seed_github_environment   = "azure-dr"
}

run "creates_the_github_oidc_provider_when_adoption_is_disabled" {
  command = plan

  assert {
    condition     = var.adopt_existing_github_oidc == false && module.github_oidc.provider_url == "https://token.actions.githubusercontent.com"
    error_message = "A fresh account must plan the configured GitHub OIDC provider when adoption is disabled."
  }
}

# A mock provider cannot read a remote import, so only the adoption path overrides the
# object that the enabled import block adopts.
run "adopts_the_github_oidc_provider_when_adoption_is_enabled" {
  command = plan

  variables {
    adopt_existing_github_oidc = true
  }

  override_resource {
    target = module.github_oidc.aws_iam_openid_connect_provider.this
    values = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }

  assert {
    condition     = var.adopt_existing_github_oidc == true && module.github_oidc.provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "An account that already has the GitHub OIDC provider must select the adoption path."
  }
}

run "lets_only_named_operators_with_mfa_assume_the_deploy_role" {
  command = plan

  assert {
    condition     = local.deploy_role_name == "lex-mts-shd-role-tfdeploy"
    error_message = "The deploy role must carry its spec 004 name."
  }

  assert {
    condition     = jsondecode(local.deploy_role_trust_policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:user/operator-a", "arn:aws:iam::123456789012:user/operator-b"] && jsondecode(local.deploy_role_trust_policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "Only the named operators may assume the deploy role."
  }

  assert {
    condition     = jsondecode(local.deploy_role_trust_policy).Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == true
    error_message = "Assuming the deploy role must require MFA."
  }
}

run "confines_the_deploy_role_to_the_project_iam" {
  command = plan

  assert {
    condition     = local.deploy_role_managed_policy_arns == ["arn:aws:iam::aws:policy/PowerUserAccess"] && alltrue([for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : !contains(flatten([statement.Action]), "iam:*") && statement.Resource != "*" || statement.Sid == "ListOidcProviders"])
    error_message = "IAM must come only from the scoped inline policy: no iam:* and no wildcard resource beyond listing OIDC providers."
  }

  assert {
    condition     = [for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : statement.Resource if statement.Sid == "ManageProjectRoles"][0] == "arn:aws:iam::123456789012:role/lex-mts-*"
    error_message = "The deploy role may manage only the project's roles."
  }

  assert {
    condition     = [for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : statement.Condition.ArnEquals["iam:PolicyARN"] if statement.Sid == "AttachOnlyTheReviewedManagedPolicies"][0] == ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly", "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy", "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    error_message = "The deploy role may attach only the managed policies the rebuilt roots use."
  }

  assert {
    condition     = [for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : statement.Condition.StringEquals["iam:PassedToService"] if statement.Sid == "PassPodIdentityRolesToEks"][0] == "pods.eks.amazonaws.com"
    error_message = "The add-on roles may be passed only to EKS Pod Identity."
  }

  assert {
    condition     = [for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : statement.Resource if statement.Sid == "DenyChangingTheDeployRoleItself" && statement.Effect == "Deny"][0] == "arn:aws:iam::123456789012:role/lex-mts-shd-role-tfdeploy"
    error_message = "The deploy role must be denied every change to itself."
  }

  assert {
    condition     = [for statement in jsondecode(local.deploy_role_policies["manage-project-iam"]).Statement : statement.Resource if statement.Sid == "DenyAssumingProjectRoles" && statement.Effect == "Deny" && statement.Action == "sts:AssumeRole"][0] == "arn:aws:iam::123456789012:role/lex-mts-*"
    error_message = "The deploy role must not assume the project roles it manages."
  }
}

run "rejects_an_operator_that_is_not_an_iam_principal" {
  command = plan

  variables {
    deploy_role_operator_arns = ["123456789012"]
  }

  expect_failures = [var.deploy_role_operator_arns]
}

run "builds_the_shared_security_names" {
  command = plan

  assert {
    condition     = local.ecr_publisher_role_name == "lex-mts-shd-role-ecrpublish" && local.flow_log_role_name == "lex-mts-shd-role-flowlogs" && local.flow_log_key_name == "lex-mts-shd-kms-flowlogs" && local.github_oidc_name == "lex-mts-shd-oidc-github"
    error_message = "The root must build the shd standard names (MTS-IAC-101)."
  }
}

run "trusts_only_reviewed_main_workflows_to_publish_images" {
  command = plan

  assert {
    condition     = jsondecode(local.ecr_publisher_trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main", "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main"]
    error_message = "Only the listed repositories' main branches may assume the publisher role."
  }

  assert {
    condition     = jsondecode(local.ecr_publisher_trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The publisher role must require the STS audience."
  }

  assert {
    condition     = jsondecode(local.ecr_publisher_policies["publish-service-images"]).Statement[1].Resource == ["arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-authapi", "arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-frontend"]
    error_message = "The publisher role may push only to the shared service repositories."
  }
}

run "limits_flow_log_delivery_to_this_account_and_its_flow_log_groups" {
  command = plan

  assert {
    condition     = jsondecode(local.flow_log_trust_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012" && jsondecode(local.flow_log_trust_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:ec2:us-east-1:123456789012:vpc-flow-log/*"
    error_message = "The flow-logs service may assume the role only for this account's flow logs."
  }

  assert {
    condition     = jsondecode(local.flow_log_key_policy).Statement[1].Principal.Service == "logs.us-east-1.amazonaws.com" && jsondecode(local.flow_log_key_policy).Statement[1].Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/*"
    error_message = "CloudWatch Logs may use the key only for the flow-log groups."
  }

  assert {
    condition     = jsondecode(local.flow_log_policies["deliver-vpc-flow-logs"]).Statement[1].Resource == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" && jsondecode(local.flow_log_policies["deliver-vpc-flow-logs"]).Statement[1].Condition.StringEquals["kms:ViaService"] == "logs.us-east-1.amazonaws.com"
    error_message = "The flow-log role may use only the flow-log key, and only through CloudWatch Logs."
  }
}

# Terraform owns every flow-log group. A role that can create one lets the flow-logs service
# re-create a group Terraform has just destroyed, and the next apply fails on it (ops spec 003 T017).
run "lets_flow_log_delivery_write_only_to_existing_flow_log_groups" {
  command = plan

  assert {
    condition     = !anytrue([for statement in jsondecode(local.flow_log_policies["deliver-vpc-flow-logs"]).Statement : contains(flatten([statement.Action]), "logs:CreateLogGroup") || contains(flatten([statement.Action]), "logs:*")])
    error_message = "The flow-log role must not be able to create a log group."
  }

  assert {
    condition     = [for statement in jsondecode(local.flow_log_policies["deliver-vpc-flow-logs"]).Statement : sort(statement.Action) if statement.Sid == "WriteVpcFlowLogGroups"][0] == tolist(["logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:PutLogEvents"])
    error_message = "The flow-log role must keep exactly the stream, event, and describe actions delivery to an existing group needs."
  }

  assert {
    condition     = [for statement in jsondecode(local.flow_log_policies["deliver-vpc-flow-logs"]).Statement : statement.Resource if statement.Sid == "WriteVpcFlowLogGroups"][0] == ["arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/*", "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/*:*"]
    error_message = "The flow-log role may write only to the flow-log groups and their streams."
  }
}

run "records_every_access_to_the_state_bucket" {
  command = plan

  assert {
    condition     = local.cloudtrail_trail_name == "lex-mts-shd-ct-tfstate" && local.cloudtrail_bucket_name == "lex-mts-shd-s3-cloudtrail" && local.cloudtrail_key_name == "lex-mts-shd-kms-cloudtrail"
    error_message = "The trail, its log bucket, and its key must carry their standard names (MTS-IAC-101)."
  }

  assert {
    condition     = local.cloudtrail_object_arn_prefixes == ["arn:aws:s3:::lex-mts-shd-s3-tfstate-123456789012/"]
    error_message = "The trail must record the objects of shd/state's bucket, read by its name, and no other bucket's."
  }

  assert {
    condition     = local.cloudtrail_log_retention == { current_days = 365, noncurrent_days = 30 }
    error_message = "Access records must be kept for the retention this root chooses, a year by default."
  }
}

run "lets_only_the_state_trail_use_its_key" {
  command = plan

  assert {
    condition     = [for statement in jsondecode(local.cloudtrail_key_policy).Statement : statement.Sid] == ["EnableAccountAdministration", "AllowCloudTrailEncryptLogs", "AllowCloudTrailDescribeKey"]
    error_message = "The key policy must carry the account delegation and the two statements the CloudTrail User Guide requires, and nothing else."
  }

  assert {
    condition     = jsondecode(local.cloudtrail_key_policy).Statement[1].Principal.Service == "cloudtrail.amazonaws.com" && jsondecode(local.cloudtrail_key_policy).Statement[1].Action == "kms:GenerateDataKey*" && jsondecode(local.cloudtrail_key_policy).Statement[1].Condition.StringEquals == { "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:123456789012:trail/lex-mts-shd-ct-tfstate" } && jsondecode(local.cloudtrail_key_policy).Statement[1].Condition.StringLike == { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:123456789012:trail/*" }
    error_message = "CloudTrail may generate data keys only for the state trail, and only for this account's trails."
  }

  assert {
    condition     = jsondecode(local.cloudtrail_key_policy).Statement[2].Action == "kms:DescribeKey" && jsondecode(local.cloudtrail_key_policy).Statement[2].Condition.StringEquals == { "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:123456789012:trail/lex-mts-shd-ct-tfstate" }
    error_message = "CloudTrail may describe the key only for the state trail."
  }

  assert {
    condition     = !anytrue([for statement in jsondecode(local.cloudtrail_key_policy).Statement : can(statement.Principal.Service) && contains(flatten([statement.Action]), "kms:Decrypt")])
    error_message = "No service may decrypt through the key policy; readers of the logs are granted decrypt in IAM."
  }
}

run "rejects_a_trail_log_retention_below_a_day" {
  command = plan

  variables {
    trail_log_retention_in_days = 0
  }

  expect_failures = [var.trail_log_retention_in_days]
}

run "rejects_an_environment_other_than_shd" {
  command = plan

  variables {
    environment = "eco"
  }

  expect_failures = [var.environment]
}

run "rejects_an_image_key_that_breaks_the_naming_rule" {
  command = plan

  variables {
    service_image_keys = ["auth-api"]
  }

  expect_failures = [var.service_image_keys]
}

run "rejects_a_github_organization_with_spaces" {
  command = plan

  variables {
    github_organization = "Micro Todo Suite"
  }

  expect_failures = [var.github_organization]
}

# The platform-mirror role (ops spec 004 T033). AWS STS offers only aud, sub, amr, email, and oaud
# as GitHub condition keys, so the workflow file is pinned through a customized subject that
# carries job_workflow_ref, not through a job_workflow_ref condition, which STS rejects.
run "trusts_only_the_reviewed_mirror_workflow_subject" {
  command = plan

  assert {
    condition     = local.platform_mirror_role_name == "lex-mts-shd-role-platmirror"
    error_message = "The mirror role must carry its standard name (MTS-IAC-101)."
  }

  assert {
    condition     = length(jsondecode(local.platform_mirror_trust_policy).Statement) == 1 && jsondecode(local.platform_mirror_trust_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" && jsondecode(local.platform_mirror_trust_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Only the GitHub OIDC provider may assume the mirror role, through one statement."
  }

  assert {
    condition     = keys(jsondecode(local.platform_mirror_trust_policy).Statement[0].Condition) == ["StringEquals"] && jsondecode(local.platform_mirror_trust_policy).Statement[0].Condition.StringEquals == { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:MicroTodoSuite/.github:ref:refs/heads/main:job_workflow_ref:MicroTodoSuite/.github/.github/workflows/mirror-platform-images.yml@refs/heads/main" }
    error_message = "The mirror role must trust exactly the STS audience and the one subject of the reviewed mirror workflow on main, compared with StringEquals and nothing else."
  }

  assert {
    condition     = !can(regex("[*?]", jsondecode(local.platform_mirror_trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]))
    error_message = "The mirror role's subject must contain no wildcard."
  }
}

run "lets_the_mirror_role_push_only_to_the_platform_mirror" {
  command = plan

  assert {
    condition     = keys(local.platform_mirror_policies) == ["mirror-platform-images"] && [for statement in jsondecode(local.platform_mirror_policies["mirror-platform-images"]).Statement : statement.Sid] == ["AuthenticateToEcr", "MirrorPlatformImages"]
    error_message = "The mirror role must carry one inline policy with exactly the ECR authentication and mirror statements."
  }

  assert {
    condition     = [for statement in jsondecode(local.platform_mirror_policies["mirror-platform-images"]).Statement : statement.Resource if statement.Sid == "MirrorPlatformImages"][0] == ["arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-platform"]
    error_message = "The mirror role may write only to lex-mts-shd-ecr-platform."
  }

  assert {
    condition     = sort([for statement in jsondecode(local.platform_mirror_policies["mirror-platform-images"]).Statement : statement.Action if statement.Sid == "MirrorPlatformImages"][0]) == tolist(["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:ListImages", "ecr:PutImage", "ecr:UploadLayerPart"])
    error_message = "The mirror role keeps exactly the legacy push, pull, and describe actions a copy and a signature need, no more."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(local.platform_mirror_policies["mirror-platform-images"]).Statement : statement.Resource != "*" || statement.Action == "ecr:GetAuthorizationToken"])
    error_message = "Only ecr:GetAuthorizationToken, which takes no resource, may name every resource."
  }

  assert {
    condition     = !contains(local.service_repository_arns, "arn:aws:ecr:us-east-1:123456789012:repository/lex-mts-shd-ecr-platform") && !contains(jsondecode(local.ecr_publisher_trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], local.platform_mirror_subject)
    error_message = "The service publisher and the mirror must stay apart: neither may reach the other's repositories or trust."
  }
}

# The DR secret-seed role (ops spec 004 T033): the only identity in the account that reads secret
# values, so it trusts one environment of one workflow file and names its four sources exactly.
run "trusts_only_the_reviewed_seed_workflow_in_its_environment" {
  command = plan

  assert {
    condition     = local.dr_secret_seed_role_name == "lex-mts-shd-role-drseed"
    error_message = "The seed role must carry its standard name (MTS-IAC-101)."
  }

  assert {
    condition     = length(jsondecode(local.dr_secret_seed_trust_policy).Statement) == 1 && jsondecode(local.dr_secret_seed_trust_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" && jsondecode(local.dr_secret_seed_trust_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Only the GitHub OIDC provider may assume the seed role, through one statement."
  }

  assert {
    condition     = keys(jsondecode(local.dr_secret_seed_trust_policy).Statement[0].Condition) == ["StringEquals"] && jsondecode(local.dr_secret_seed_trust_policy).Statement[0].Condition.StringEquals == { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:MicroTodoSuite/.github:environment:azure-dr:job_workflow_ref:MicroTodoSuite/.github/.github/workflows/sync-dr-secrets.yml@refs/heads/main" }
    error_message = "The seed role must trust exactly the STS audience and the one subject that pins repository, GitHub environment, and workflow file."
  }

  assert {
    condition     = !can(regex("[*?]", jsondecode(local.dr_secret_seed_trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]))
    error_message = "The seed role's subject must contain no wildcard."
  }
}

run "lets_the_seed_role_read_only_the_four_approved_sources" {
  command = plan

  assert {
    condition     = keys(local.dr_secret_seed_policies) == ["read-exact-dr-seed-secrets"] && length(jsondecode(local.dr_secret_seed_policies["read-exact-dr-seed-secrets"]).Statement) == 1
    error_message = "The seed role must carry one inline policy with one statement."
  }

  assert {
    condition     = sort(jsondecode(local.dr_secret_seed_policies["read-exact-dr-seed-secrets"]).Statement[0].Action) == tolist(["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"])
    error_message = "The seed role may only describe and read a secret; it may not list, write, or delete one."
  }

  # Secrets Manager appends a hyphen and six random characters to every ARN; the six ? match
  # exactly those and nothing longer (Secrets Manager User Guide, identity-based policies).
  assert {
    condition     = jsondecode(local.dr_secret_seed_policies["read-exact-dr-seed-secrets"]).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fdev-sm-grafanaadm-??????", "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-jwtprd-??????", "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-slackobs-??????", "arn:aws:secretsmanager:us-east-1:123456789012:secret:lex-mts-fprd-sm-slacksec-??????"]
    error_message = "The seed role may read exactly the production JWT, the two production Slack webhooks, and the full-profile Grafana administrator."
  }

  assert {
    condition     = !anytrue([for arn in jsondecode(local.dr_secret_seed_policies["read-exact-dr-seed-secrets"]).Statement[0].Resource : strcontains(arn, "*")])
    error_message = "No source ARN may use *, which would match any secret sharing the prefix."
  }
}

run "rejects_a_seed_environment_with_a_wildcard" {
  command = plan

  variables {
    dr_seed_github_environment = "azure-*"
  }

  expect_failures = [var.dr_seed_github_environment]
}

run "rejects_platform_as_a_service_key" {
  command = plan

  variables {
    service_image_keys = ["frontend", "platform"]
  }

  expect_failures = [var.service_image_keys]
}
