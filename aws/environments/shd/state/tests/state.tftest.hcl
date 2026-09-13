# Plan-time tests of the shd/state root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias = "principal"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/terraform-deploy/lex-mts-shd-state"
      user_id    = "AROAEXAMPLE:lex-mts-shd-state"
    }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
}

variables {
  client          = "lex"
  project         = "mts"
  environment     = "shd"
  aws_account_id  = "123456789012"
  aws_region      = "us-east-1"
  deploy_role_arn = "arn:aws:iam::123456789012:role/terraform-deploy"
}

run "names_the_state_bucket_and_key_from_the_governance_codes" {
  command = plan

  assert {
    condition     = local.state_bucket_name == "lex-mts-shd-s3-tfstate" && local.state_key_name == "lex-mts-shd-kms-tfstate"
    error_message = "The root must build the shd standard names; the module appends the account ID to the bucket (MTS-IAC-101)."
  }

  assert {
    condition     = output.state_kms_alias_name == "alias/lex-mts-shd-kms-tfstate"
    error_message = "The state key's alias must be alias/ followed by the shd standard name."
  }
}

run "rejects_an_environment_other_than_shd" {
  command = plan

  variables {
    environment = "eco"
  }

  expect_failures = [var.environment]
}

run "rejects_an_account_that_is_not_twelve_digits" {
  command = plan

  variables {
    aws_account_id = "12345"
  }

  expect_failures = [var.aws_account_id]
}

run "rejects_a_deploy_principal_that_is_not_a_role" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::123456789012:user/operator"
  }

  expect_failures = [var.deploy_role_arn]
}
