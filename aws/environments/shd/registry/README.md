# shd/registry

The shared service image registry of the rebuilt layout (ops spec 004 T010,
ai-agents specs/001 T025). It creates one ECR repository per service through
`ecr-repository-v1.0.0`, named `lex-mts-shd-ecr-<key>`:

| Key | Repository | Legacy repository |
| --- | --- | --- |
| `authapi` | `lex-mts-shd-ecr-authapi` | `microtodosuite/auth-api` |
| `frontend` | `lex-mts-shd-ecr-frontend` | `microtodosuite/frontend` |
| `logmsgproc` | `lex-mts-shd-ecr-logmsgproc` | `microtodosuite/log-message-processor` |
| `todosapi` | `lex-mts-shd-ecr-todosapi` | `microtodosuite/todos-api` |
| `usersapi` | `lex-mts-shd-ecr-usersapi` | `microtodosuite/users-api` |

The module sets the same protection the legacy repositories had:
- immutable tags;
- scanning on push;
- AES-256 encryption;
- untagged images expired after 30 days;
- `prevent_destroy`.

`shd/security`'s publisher role may push only to these names, so both roots
take the same `service_image_keys`.

## The platform image mirror

`lex-mts-shd-ecr-platform` holds every checksum-locked third-party platform
image: controllers, exporters, and dashboards (ops spec 004 T032). The reviewed
`mirror-platform-images.yml` workflow of the `.github` repository copies each
one by digest, under `shd/security`'s `lex-mts-shd-role-platmirror`, so a
cluster never resolves an upstream registry at runtime.

It succeeds the legacy `microtodosuite/platform` of
`aws/modules/environment-foundation` (`platform-mirror.tf`), which no rebuilt
root created (audit 2026-09-27, D8). The name changes because MTS-IAC-101
names every resource, and `ecr-repository` rejects a name with a path. It keeps
the legacy protection through its own call of the same `ecr-repository-v1.0.0`
release: immutable tags, scan on push, AES-256, no force delete,
`prevent_destroy`, and one lifecycle rule that expires only untagged images
after 30 days, so a pinned mirrored digest never expires. That release's own
tests prove the protection, and this root's tests pin the call to it.

A separate call keeps the mirror apart from the service repositories:
`service_image_keys` rejects `platform`, so the publisher role can never reach
it, and the mirror role can reach nothing else.

The legacy images are not rebuilt. They are copied by digest, with their
signatures and attestations, during the approved cutover (ops spec 004
FR-004).

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                         # fill aws_account_id
cp registry.s3.tfbackend.example registry.s3.tfbackend   # fill from shd/state's outputs
terraform -chdir=aws/environments/shd/registry init -backend-config=registry.s3.tfbackend
terraform -chdir=aws/environments/shd/registry plan -input=false -var-file=shd.tfvars -out=shd-registry.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107). The state key is new, so the apply records a `no-prior-state`
receipt instead of a state backup.

## Outputs

`service_repository_urls` and `service_repository_arns`, keyed by service key;
`platform_mirror_repository_url` and `platform_mirror_repository_arn`.
