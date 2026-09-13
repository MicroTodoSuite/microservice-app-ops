# Plan-time tests of the shd/dns root against a mocked AWS provider (PC-IAC-018).
mock_provider "aws" {
  alias = "principal"
}

# A mock provider cannot import, so the adopted zone is overridden instead.
override_resource {
  target = module.public_zone.aws_route53_zone.this
  values = { zone_id = "Z0000000000000000000" }
}

variables {
  client           = "lex"
  project          = "mts"
  environment      = "shd"
  aws_account_id   = "123456789012"
  aws_region       = "us-east-1"
  deploy_role_arn  = "arn:aws:iam::123456789012:role/terraform-deploy"
  public_zone_name = "microtodosuite.abrdns.com"
  public_zone_id   = "Z0000000000000000000"
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
    public_zone_id = "/hostedzone/Z0000000000000000000"
  }

  expect_failures = [var.public_zone_id]
}
