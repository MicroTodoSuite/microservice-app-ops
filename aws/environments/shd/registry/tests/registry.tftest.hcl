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

# The protection comes from the pinned module release, so this run plans that exact release as
# `terraform init` installed it for module.platform_mirror, with the inputs the root passes it.
# It needs the default data directory, which the iac-checks workflow uses.
run "keeps_the_platform_mirror_immutable_scanned_and_undeletable" {
  command = plan

  module {
    source = "./.terraform/modules/platform_mirror/ecr-repository"
  }

  providers = {
    aws.project = aws.principal
  }

  variables {
    repositories    = { platform = { name = "lex-mts-shd-ecr-platform" } }
    additional_tags = { Content = "third-party-platform-images" }
  }

  assert {
    condition     = aws_ecr_repository.this["platform"].image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.this["platform"].force_delete == false
    error_message = "A mirrored digest must never be overwritten by a re-tag, and the repository must not be force-deletable."
  }

  assert {
    condition     = aws_ecr_repository.this["platform"].image_scanning_configuration[0].scan_on_push == true && aws_ecr_repository.this["platform"].encryption_configuration[0].encryption_type == "AES256"
    error_message = "Every mirrored image must be scanned on push and encrypted at rest."
  }

  assert {
    condition     = [for rule in jsondecode(aws_ecr_lifecycle_policy.this["platform"].policy).rules : rule.selection] == [{ tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 30 }]
    error_message = "The lifecycle policy may reclaim only untagged layers after 30 days; a pinned mirrored image must never expire."
  }
}
