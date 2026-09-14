# shd/dns

The account's public DNS root of the rebuilt layout (ops spec 004 T010,
ai-agents specs/001 T025). It adopts the existing public hosted zone
`microtodosuite.abrdns.com` through `route53-zone-v1.0.0` and an `import`
block. The zone is never created or renamed here: its name servers are
delegated at the registrar, and a new zone would get new ones (ops spec 004
FR-005).

| Resource | Module | Name |
| --- | --- | --- |
| Public hosted zone | `route53-zone-v1.0.0` | the domain; `Name` tag `lex-mts-shd-dns-public` |
| Canonical public hosted zone, created | `route53-zone-v1.0.0` | the domain; `Name` tag `lex-mts-shd-dns-canonical` |

**The comment** is the legacy root's, word for word, so the first plan changes
only the zone's tags.

**Protection.** The module keeps `force_destroy = false` and
`prevent_destroy`.

**Records** belong to the roots that own their targets. This root holds none.

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
replaced nor used for new records.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                 # fill aws_account_id and public_zone_id
cp dns.s3.tfbackend.example dns.s3.tfbackend     # fill from shd/state's outputs
terraform -chdir=aws/environments/shd/dns init -backend-config=dns.s3.tfbackend
terraform -chdir=aws/environments/shd/dns plan -input=false -var-file=shd.tfvars -out=shd-dns.tfplan
```

`public_zone_id` is the legacy dev root's `public_hosted_zone_id` output. An
apply uses only the saved plan, after the maintainer approves it and after a
timestamped state backup (MTS-IAC-107).

## Outputs

`public_zone_id`, `public_zone_arn`, and `public_zone_name_server_names` for
the legacy zone; `canonical_zone_id`, `canonical_zone_arn`, and
`canonical_zone_name_server_names` for the canonical one.
