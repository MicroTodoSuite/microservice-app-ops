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
}

# A mock provider cannot import, so the adopted OIDC provider is overridden instead.
override_resource {
  target = module.github_oidc.aws_iam_openid_connect_provider.this
  values = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
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
