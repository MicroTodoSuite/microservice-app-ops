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

**The comment** is the legacy root's, word for word, so the first plan changes
only the zone's tags.

**Protection.** The module keeps `force_destroy = false` and
`prevent_destroy`.

**Records** belong to the roots that own their targets. This root holds none.

**The canonical `microtodosuite.online` zone** of full-platform spec 009 was
never created. It is not part of this root.

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

`public_zone_id`, `public_zone_arn`, and `public_zone_name_server_names`.
