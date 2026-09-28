# Plan-time tests of the shd/dns root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias           = "principal"
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = { zone_id = "Z1111111111111111111" }
  }
}

variables {
  client                    = "lex"
  project                   = "mts"
  environment               = "shd"
  aws_account_id            = "123456789012"
  aws_region                = "us-east-1"
  deploy_role_arn           = "arn:aws:iam::123456789012:role/terraform-deploy"
  manage_legacy_public_dns  = false
  public_zone_name          = "microtodosuite.abrdns.com"
  public_zone_id            = null
  adopt_existing_public_dns = false
  canonical_zone_name       = "microtodosuite.online"
}

run "creates_only_the_canonical_zone_when_legacy_management_is_disabled" {
  command = plan

  assert {
    condition     = length(module.public_zone) == 0 && module.canonical_zone.zone_name == "microtodosuite.online"
    error_message = "A fresh account must plan exactly the canonical zone when legacy-zone management is disabled."
  }

  assert {
    condition     = output.public_zone_id == null && output.public_zone_arn == null && output.public_zone_name_server_names == null
    error_message = "Legacy-zone outputs must be null when the root does not manage the legacy zone."
  }
}

# A mock provider cannot read a remote import, so only the adoption path overrides the
# object that the enabled import block adopts.
run "adopts_the_public_zone_when_adoption_is_enabled" {
  command = plan

  variables {
    manage_legacy_public_dns  = true
    adopt_existing_public_dns = true
    public_zone_id            = "Z0000000000000000000"
  }

  override_resource {
    target = module.public_zone[0].aws_route53_zone.this
    values = { zone_id = "Z0000000000000000000" }
  }

  assert {
    condition     = length(module.public_zone) == 1 && var.adopt_existing_public_dns == true && module.public_zone[0].zone_id == var.public_zone_id
    error_message = "An account that already has the public zone must select the adoption path with its hosted-zone ID."
  }
}

run "rejects_adoption_when_legacy_management_is_disabled" {
  command = plan

  variables {
    manage_legacy_public_dns  = false
    adopt_existing_public_dns = true
    public_zone_id            = "Z0000000000000000000"
  }

  expect_failures = [var.adopt_existing_public_dns]
}

run "adopts_the_zone_under_its_standard_name_and_legacy_comment" {
  command = plan

  assert {
    condition     = local.public_zone_standard_name == "lex-mts-shd-dns-public"
    error_message = "The zone's Name tag must be the shd standard name (MTS-IAC-101)."
  }

  assert {
    condition     = local.public_zone_comment == "Public hosted zone for microtodosuite.abrdns.com; registrar delegation remains manual."
    error_message = "The comment must stay the legacy one, so the import changes only tags."
  }
}

run "creates_the_canonical_zone_under_its_standard_name" {
  command = plan

  assert {
    condition     = local.canonical_zone_standard_name == "lex-mts-shd-dns-canonical"
    error_message = "The canonical zone's Name tag must be the shd standard name (MTS-IAC-101)."
  }

  assert {
    condition     = local.canonical_zone_comment == "Canonical public hosted zone for microtodosuite.online; registrar delegation remains manual."
    error_message = "The comment must name the domain and say that its delegation is set at the registrar."
  }

  assert {
    condition     = module.canonical_zone.zone_name == "microtodosuite.online"
    error_message = "The canonical zone must serve exactly the domain the root was given."
  }
}

run "rejects_a_canonical_zone_that_repeats_the_legacy_zone" {
  command = plan

  variables {
    canonical_zone_name = "microtodosuite.abrdns.com"
  }

  expect_failures = [var.canonical_zone_name]
}

run "rejects_a_canonical_zone_name_with_a_trailing_dot" {
  command = plan

  variables {
    canonical_zone_name = "microtodosuite.online."
  }

  expect_failures = [var.canonical_zone_name]
}

run "rejects_an_environment_other_than_shd" {
  command = plan

  variables {
    environment = "eco"
  }

  expect_failures = [var.environment]
}

run "rejects_a_zone_name_with_a_trailing_dot" {
  command = plan

  variables {
    public_zone_name = "microtodosuite.abrdns.com."
  }

  expect_failures = [var.public_zone_name]
}

run "rejects_a_zone_id_with_the_hostedzone_prefix" {
  command = plan

  variables {
    manage_legacy_public_dns  = true
    adopt_existing_public_dns = true
    public_zone_id            = "/hostedzone/Z0000000000000000000"
  }

  expect_failures = [var.public_zone_id]
}
