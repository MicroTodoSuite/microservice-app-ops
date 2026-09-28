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
    condition     = concat([for zone in module.public_zone : zone.zone_name], [module.canonical_zone.zone_name]) == ["microtodosuite.online"]
    error_message = "A fresh account must plan exactly one zone, the canonical microtodosuite.online zone, when legacy-zone management is disabled."
  }

  assert {
    condition     = output.public_zone_id == null && output.public_zone_arn == null && output.public_zone_name_server_names == null
    error_message = "Legacy-zone outputs must be null when the root does not manage the legacy zone."
  }
}

# The records and health checks point at provider endpoints that do not exist until their
# destinations are live, so the root's defaults plan none of them (gitops spec 009 T134).
run "plans_no_destination_record_or_health_check_by_default" {
  command = plan

  assert {
    condition     = var.destination_provider_fqdns == {} && length(aws_route53_record.destination) == 0 && length(aws_route53_health_check.destination) == 0
    error_message = "The default plan must create no destination record and no health check until an operator supplies a reviewed provider FQDN."
  }

  assert {
    condition     = output.destination_record_fqdns == {} && output.destination_health_check_ids == {}
    error_message = "The destination outputs must be empty while no destination is enabled."
  }
}

run "creates_the_exact_destination_records_and_https_health_checks" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-dev        = "full-dev.example.net"
      full-staging    = "full-staging.example.net"
      full-prod-aws   = "full-prod-aws.example.net"
      full-prod-azure = "full-prod-azure.example.net"
      sonar-full-dev  = "sonar-full-dev.example.net"
    }
  }

  assert {
    condition = {
      for key, record in aws_route53_record.destination : key => {
        name    = record.name
        type    = record.type
        zone_id = record.zone_id
        records = record.records
      }
      } == {
      for key, target in var.destination_provider_fqdns : key => {
        name    = "${key}.microtodosuite.online"
        type    = "CNAME"
        zone_id = module.canonical_zone.zone_id
        records = [target]
      }
    }
    error_message = "The one canonical zone must contain exactly the four destination CNAMEs and sonar-full-dev.microtodosuite.online, each targeting its reviewed provider FQDN."
  }

  assert {
    condition = {
      for key, check in aws_route53_health_check.destination : key => {
        fqdn = check.fqdn
        port = check.port
        type = check.type
      }
      } == {
      for key in ["full-dev", "full-staging", "full-prod-aws", "full-prod-azure"] : key => {
        fqdn = var.destination_provider_fqdns[key]
        port = 443
        type = "HTTPS"
      }
    }
    error_message = "Every workload destination must have its own HTTPS health check against the reviewed provider FQDN."
  }
}

run "keeps_shared_production_routing_absent_by_default" {
  command = plan

  assert {
    condition     = var.enable_active_active == false && length(aws_route53_record.active_active) == 0
    error_message = "The default plan must contain zero app.microtodosuite.online routing records."
  }
}

run "rejects_an_empty_destination_provider_fqdn" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-dev        = "full-dev.example.net"
      full-staging    = "full-staging.example.net"
      full-prod-aws   = "full-prod-aws.example.net"
      full-prod-azure = ""
      sonar-full-dev  = "sonar-full-dev.example.net"
    }
  }

  expect_failures = [var.destination_provider_fqdns]
}

run "enables_one_destination_at_a_time" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-prod-azure = "full-prod-azure.example.net"
    }
  }

  assert {
    condition     = keys(aws_route53_record.destination) == ["full-prod-azure"] && keys(aws_route53_health_check.destination) == ["full-prod-azure"] && length(aws_route53_record.active_active) == 0
    error_message = "Supplying one provider FQDN must enable only that destination's CNAME and health check, and no shared routing record."
  }
}

run "rejects_an_unknown_destination" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-prod-gcp = "full-prod-gcp.example.net"
    }
  }

  expect_failures = [var.destination_provider_fqdns]
}

run "rejects_a_provider_fqdn_with_a_trailing_dot" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-dev = "full-dev.example.net."
    }
  }

  expect_failures = [var.destination_provider_fqdns]
}

run "rejects_a_provider_fqdn_inside_the_canonical_zone" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-dev = "full-staging.microtodosuite.online"
    }
  }

  expect_failures = [var.destination_provider_fqdns]
}

# Failover routing for the common hostname is T139's plan and T140's apply. The root may
# express it only when both production destinations are live and health-checked.
run "routes_the_common_hostname_by_health_evaluated_failover_only_when_enabled" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-dev        = "full-dev.example.net"
      full-staging    = "full-staging.example.net"
      full-prod-aws   = "full-prod-aws.example.net"
      full-prod-azure = "full-prod-azure.example.net"
      sonar-full-dev  = "sonar-full-dev.example.net"
    }
    enable_active_active = true
  }

  assert {
    condition = {
      for key, record in aws_route53_record.active_active : key => {
        name            = record.name
        type            = record.type
        records         = record.records
        set_identifier  = record.set_identifier
        failover        = record.failover_routing_policy[0].type
        health_check_id = record.health_check_id
      }
      } == {
      PRIMARY = {
        name            = "app.microtodosuite.online"
        type            = "CNAME"
        records         = ["full-prod-aws.example.net"]
        set_identifier  = "full-prod-aws"
        failover        = "PRIMARY"
        health_check_id = aws_route53_health_check.destination["full-prod-aws"].id
      }
      SECONDARY = {
        name            = "app.microtodosuite.online"
        type            = "CNAME"
        records         = ["full-prod-azure.example.net"]
        set_identifier  = "full-prod-azure"
        failover        = "SECONDARY"
        health_check_id = aws_route53_health_check.destination["full-prod-azure"].id
      }
    }
    error_message = "Enabled routing must be a health-evaluated AWS primary and Azure secondary for app.microtodosuite.online, nothing else."
  }
}

run "rejects_shared_routing_without_both_production_destinations" {
  command = plan

  variables {
    destination_provider_fqdns = {
      full-prod-aws = "full-prod-aws.example.net"
    }
    enable_active_active = true
  }

  expect_failures = [var.enable_active_active]
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
