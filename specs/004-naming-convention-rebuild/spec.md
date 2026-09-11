# Feature Specification: Naming-Convention Adoption and Infrastructure Rebuild

**Feature Branch**: `docs/spec-004-naming-rebuild`
**Created**: 2026-09-11
**Status**: Draft — execution requires the constitution 4.0.0 amendment
**Input**: Maintainer decision G3 (2026-09-11): adopt the naming convention
completely and now; bring down every deployed resource that must change, rename
it, and recreate it — EKS included — after preserving everything persistent or
sensitive; validate; leave no orphan and no reference to an old name.

## Scope

Every Terraform root and module in this repository, and every deployed AWS
resource in account `575172595729`. The convention is
`microservice-app-ai-agents/rules/iac/MTS-IAC-101`; the rules it implements are
PC-IAC-003, PC-IAC-004, PC-IAC-022, PC-IAC-023, and PC-IAC-025.

The rebuild also adopts the domain layout of PC-IAC-022. Roots, state keys, and
resource addresses change anyway when everything is recreated, so the layout
costs no migration now and would cost a second outage later. Modules are
decomposed under PC-IAC-023 and stay in this repository, consumed by local path,
under the recorded transition exception to PC-IAC-015; extracting them to
`terraform-aws-modules` afterwards keeps every address and produces empty plans.

## User Stories

### US1 — Every deployed resource carries a conforming name (P1)

**Acceptance**: after the rebuild, every resource in the account that Terraform
manages has a physical name and `Name` tag matching MTS-IAC-101 or a listed
exception, and `aws resourcegroupstaggingapi get-resources` returns no resource
with a pre-convention name.

### US2 — Nothing persistent is lost (P1)

**Acceptance**: every item inventoried as persistent or sensitive is restored or
reproduced: state history archived, both Slack webhook values present under the
new secret names, every released image present under the new repository names
with the same digest and a verifiable signature, observability volumes
snapshotted, the public zone and its delegation unchanged.

### US3 — The platform works again (P1)

**Acceptance**: the economical cluster is recreated, ArgoCD reconciles every
Application Healthy and Synced, the five services pass their cross-service
checks, CI publishes an image through the renamed publisher role, and every other
root's refreshed plan is `no-op`.

### US4 — No orphans and no old references (P2)

**Acceptance**: no volume, Elastic IP, network interface, log group, KMS key
pending no deletion, role, policy, or repository from the old estate remains
except those scheduled for deletion by AWS itself; `git grep` across every
repository finds no old physical name outside specifications, evidence, and this
feature's inventory.

## Functional Requirements

- **FR-001**: The rebuild MUST NOT start before the constitution amendment
  permitting it is merged.
- **FR-002**: Every destroy and apply MUST follow MTS-IAC-107: external backup,
  saved plan inspected from JSON, approval of that exact plan.
- **FR-003**: Secret values MUST be copied without being printed or written to
  disk in clear text.
- **FR-004**: Images MUST be copied with their digests preserved, together with
  their signatures and SBOM attestations; nothing is rebuilt to recreate them.
- **FR-005**: The public zone `microtodosuite.abrdns.com` and the GitHub OIDC
  provider MUST be kept and moved into the new roots by import, not recreated:
  neither name is governed by the convention, and recreating the zone would
  change its name servers.
- **FR-006**: The GitOps values — account, role ARNs, registry names, secret
  names — MUST come from the new roots' outputs, not be typed (MTS-IAC-105).
- **FR-007**: The account MUST reach every root as `var.aws_account_id` from the
  single declaration (MTS-IAC-103).

## Out of Scope

- Extracting modules to `terraform-aws-modules` (a follow-up with empty plans).
- Deploying the full profile; its roots are renamed and restructured in code only.
- Human IAM users, which Terraform does not manage.
