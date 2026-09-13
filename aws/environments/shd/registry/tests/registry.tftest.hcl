# Plan-time tests of the shd/registry root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias = "principal"
}

variables {
  client             = "lex"
  project            = "mts"
  environment        = "shd"
  aws_account_id     = "123456789012"
  aws_region         = "us-east-1"
  deploy_role_arn    = "arn:aws:iam::123456789012:role/terraform-deploy"
  service_image_keys = ["authapi", "logmsgproc"]
}

run "builds_one_standard_repository_per_service" {
  command = plan

  assert {
    condition     = local.service_repositories == { authapi = { name = "lex-mts-shd-ecr-authapi" }, logmsgproc = { name = "lex-mts-shd-ecr-logmsgproc" } }
    error_message = "Every service key must become one lex-mts-shd-ecr-<key> repository (MTS-IAC-101)."
  }
}

run "rejects_an_environment_other_than_shd" {
  command = plan

  variables {
    environment = "eco"
  }

  expect_failures = [var.environment]
}

run "rejects_a_key_that_breaks_the_naming_rule" {
  command = plan

  variables {
    service_image_keys = ["auth-api"]
  }

  expect_failures = [var.service_image_keys]
}

run "rejects_a_repeated_key" {
  command = plan

  variables {
    service_image_keys = ["authapi", "authapi"]
  }

  expect_failures = [var.service_image_keys]
}

run "rejects_a_name_longer_than_the_standard_allows" {
  command = plan

  variables {
    project = "microtodosuite"
  }

  expect_failures = [var.service_image_keys]
}
