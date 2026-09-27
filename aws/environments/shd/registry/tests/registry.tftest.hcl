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

# The platform image mirror (ops spec 004 T032): one repository for every locked third-party
# platform image, apart from the service repositories so the publisher role never reaches it.
run "builds_the_platform_mirror_apart_from_the_service_repositories" {
  command = plan

  assert {
    condition     = local.platform_mirror_repositories == { platform = { name = "lex-mts-shd-ecr-platform" } }
    error_message = "The platform mirror must be the one repository lex-mts-shd-ecr-platform (MTS-IAC-101), the successor of microtodosuite/platform."
  }

  assert {
    condition     = module.platform_mirror.repository_names == { platform = "lex-mts-shd-ecr-platform" }
    error_message = "The root must create the platform mirror through its own module call."
  }

  assert {
    condition     = !contains(values(module.service_images.repository_names), "lex-mts-shd-ecr-platform")
    error_message = "The platform mirror must not be one of the service repositories the publisher role pushes to."
  }
}

run "rejects_platform_as_a_service_key" {
  command = plan

  variables {
    service_image_keys = ["authapi", "platform"]
  }

  expect_failures = [var.service_image_keys]
}

# The protection comes from the pinned ecr-repository release, whose own tests prove it
# (terraform-aws-modules ecr-repository/tests, run "creates_immutable_scanned_repositories"):
# immutable tags, scan on push, AES-256, no force delete, and one lifecycle rule that expires
# only untagged images after 30 days. Terraform 1.15 cannot validate a run that plans that
# module directly, because it declares configuration_aliases, so this run pins the call to that
# release and to the release's default expiry instead.
run "keeps_the_platform_mirror_on_the_immutable_module_release" {
  command = plan

  assert {
    condition     = length(module.platform_mirror.repository_names) == 1 && strcontains(file("main.tf"), "module \"platform_mirror\" {\n  source = \"git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//ecr-repository?ref=ecr-repository-v1.0.0\"\n")
    error_message = "The platform mirror must be created by the ecr-repository-v1.0.0 release, whose tests prove the immutable, scanned, undeletable repository."
  }

  assert {
    condition     = length(module.platform_mirror.repository_names) == 1 && !strcontains(file("main.tf"), "untagged_image_expiry_days")
    error_message = "The mirror must keep the release's lifecycle policy: only untagged images expire, after 30 days; a pinned mirrored image never does."
  }
}
