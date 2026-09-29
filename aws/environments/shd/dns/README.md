# shd/dns

The account's public DNS root of the rebuilt layout (ops spec 004 T010 and
T037, ai-agents specs/001 T025). It always manages the canonical public hosted
zone `microtodosuite.online`. Legacy-zone management defaults off, so a fresh
account does not create or manage `microtodosuite.abrdns.com`.

An account that still owns the legacy zone can set
`manage_legacy_public_dns = true`, `adopt_existing_public_dns = true`, and its
`public_zone_id` to adopt it through `route53-zone-v1.0.0`. Adoption is refused
when management is disabled. The legacy zone MUST NOT be renamed or recreated:
its name servers are delegated at the registrar, and a new zone would get new
ones (ops spec 004 FR-005).

| Resource | Module | Name |
| --- | --- | --- |
| Legacy public hosted zone, optional and adopted | `route53-zone-v1.0.0` | the domain; `Name` tag `lex-mts-shd-dns-public` |
| Canonical public hosted zone, created | `route53-zone-v1.0.0` | the domain; `Name` tag `lex-mts-shd-dns-canonical` |
| Destination CNAMEs, off by default | `aws_route53_record.destination` | `<destination>.microtodosuite.online` |
| Destination HTTPS health checks, off by default | `aws_route53_health_check.destination` | `Name` tag `lex-mts-shd-hc-<destination>` |
| Shared failover pair, off by default | `aws_route53_record.active_active` | `app.microtodosuite.online` |

**The legacy comment** is the legacy root's, word for word, so an adoption plan
changes only the zone's tags.

**Protection.** The module keeps `force_destroy = false` and
`prevent_destroy`.

**Destination records** (gitops spec 009 T122 and T134) are inert by default.
`destination_provider_fqdns` maps each destination's subdomain to its reviewed
provider FQDN; its default is empty, so a plan creates no record and no health
check. Each key an operator adds creates exactly one CNAME
`<key>.microtodosuite.online` to that FQDN, and each workload destination
(`full-dev`, `full-staging`, `full-prod-aws`, `full-prod-azure`, not
`sonar-full-dev`) one Route 53 HTTPS health check on port 443 against the
provider FQDN. The input fails closed: an unknown key, an empty or malformed
FQDN, a trailing dot, or a target inside the canonical zone fails the plan.

**The shared hostname** `app.microtodosuite.online` has no record while
`enable_active_active = false`, the default. When T139's separately approved
plan turns it on, it becomes a failover pair: the AWS-production provider FQDN
as the health-evaluated primary and the Azure one as the secondary, and the
variable refuses to turn on unless both production destinations are present.
Latency-based active-active stays unavailable until a replicated data store
exists.

**The canonical zone** `microtodosuite.online` is the only public domain for
new records (gitops spec 009 FR-044), and every profile's subdomains live in
it:

- `eco.microtodosuite.online` and `dev`, `staging`, and `demo.eco` for the
  economical environments;
- `full-dev`, `full-staging`, and `full-prod-aws.microtodosuite.online` for
  the full clusters;
- `app.microtodosuite.online`, reserved for the final production traffic,
  which needs a named traffic owner.

Unlike the legacy zone, it is created here, and gets new name servers. The
registrar, Namecheap, must delegate the domain to the four names in
`canonical_zone_name_server_names`, under **Nameservers → Custom DNS**. Until
it does, nothing in the zone resolves publicly. The legacy zone is neither
replaced nor used for new records. When its management is disabled, all three
legacy outputs are `null`.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                 # fill aws_account_id; legacy adoption is optional
cp dns.s3.tfbackend.example dns.s3.tfbackend     # fill from shd/state's outputs
terraform -chdir=aws/environments/shd/dns init -backend-config=dns.s3.tfbackend
terraform -chdir=aws/environments/shd/dns plan -input=false -var-file=shd.tfvars -out=shd-dns.tfplan
```

When legacy management and adoption are enabled, `public_zone_id` is the legacy
dev root's `public_hosted_zone_id` output. An apply uses only the saved plan,
after the maintainer approves it and after a timestamped state backup
(MTS-IAC-107).

## Outputs

`public_zone_id`, `public_zone_arn`, and `public_zone_name_server_names` for
the legacy zone when managed (otherwise `null`); `canonical_zone_id`,
`canonical_zone_arn`, and
`canonical_zone_name_server_names` for the canonical one;
`destination_record_names` and `destination_health_check_ids` for the enabled
destinations, empty by default.
