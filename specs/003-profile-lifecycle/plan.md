# Implementation Plan: Profile-Aware AWS Runtime Lifecycle (003)

**Branch**: `feat/profile-lifecycle` | **Date**: 2026-09-10 | **Spec**: [spec.md](./spec.md)

## Summary

Add a default-on runtime boundary to the existing foundation state instead of moving durable resources between state files. Build a profile-aware wrapper that produces saved plan bundles, validates their provenance, and applies only the reviewed artifacts. Keep GitOps quiescence as an explicit external gate.

## Design

### State-safe runtime boundary

The shared foundation module receives `runtime_enabled`. Runtime singleton resources and modules become conditional instances. Every address that changes from a singleton to index zero gets a `moved` block. Existing `for_each` addresses retain their keys and use an empty collection while disabled.

This avoids cross-state moves for write-only secret versions and protected hosted zones. It also keeps rollback simple: setting `runtime_enabled=true` recreates the runtime in the same state while all durable addresses remain unchanged.

### Profile orchestration

The wrapper owns only orchestration and evidence. Since 2026-09-13 it plans the rebuilt roots (FR-021 to FR-026):

| Profile | Up order | Down order |
| --- | --- | --- |
| `economical` | `eco/networking` (NAT on), `eco/workload`, `eco/security-irsa` | `eco/security-irsa` (destroy), `eco/workload` (destroy), `eco/networking` (NAT off) |
| `full` | `shd/networking`, `fdev`/`fstg`/`fprd` networking (transit on), `fdev`/`fstg`/`fprd` workload | the three workload roots (destroy), the three spokes (transit off), `shd/networking` (destroy) |

The persistent roots, `shd/state`, `shd/security`, `shd/registry`, `shd/dns`, and `eco/security`, never appear. `eco/networking` is not destroyed: `eco/security`'s security groups belong to its VPC. Its NAT gateways and their public IPv4 addresses are charged hourly, so they are the part that goes down.

**Second bundles.** Each bundle records its `pass`:
- `unprotect` (down, while the cluster in `eco/workload`'s state has deletion protection on). Amazon EKS refuses to delete a protected cluster. The bundle therefore holds only an `eco/workload` plan with `cluster_deletion_protection=false`, and that plan must delete nothing. The operator applies it and plans down again. One bundle cannot hold both plans: applying the first changes the state the destroy plan would have been saved against.
- `cluster-first` (up, while no cluster exists). The IRSA pass reads the cluster's OIDC issuer, so the bundle holds `eco/networking` and `eco/workload`, and the next up bundle adds the IRSA pass.
- `hub-first` (full up, while `shd/networking`'s state holds no transit gateway). The spokes read the hub's transit gateway at plan time, so the bundle holds only the hub, and the next up bundle adds the spokes and the clusters.
- `complete` in every other case.

The spokes are never destroyed, for the same reason as `eco/networking`: each environment's security groups belong to its VPC. The hub is destroyed last, because a transit gateway cannot be deleted while an attachment remains.

The wrapper reads the cluster from `terraform show -json` of `eco/workload`'s state.

**Down-plan audits.** Every root's plan JSON passes the durable-delete filter. The `eco/networking` plan and each spoke's plan also pass `scripts/aws-profile-egress-deletes.jq`. It allows deleting only NAT gateways, Elastic IPs, a spoke's transit attachment, route table association, and transit gateway routes, and the `aws_route.private_nat` and `aws_route.private_transit` routes.

**Account and region.** The wrapper compares the STS account with `config/aws-account.env` and with each root's `aws_account_id`. It reads a single `aws_region` across the profile's roots.

#### Legacy roots (2026-09-10 design)

The rest of this section, and the state-safe runtime boundary above, describe the legacy roots, which the wrapper no longer plans. Every release before this change maps them; `v1.19.0` was the latest on 2026-09-13.

| Profile | Up order | Down order |
| --- | --- | --- |
| `economical` | dev foundation | dev foundation |
| `full` | shared egress, full-dev, demo-full, full-prod | full-prod, demo-full, full-dev, shared egress |

Foundation down plans use `-var=runtime_enabled=false`. The final full-profile egress plan uses Terraform destroy mode only after all three foundation runtime plans have been created. No backend, ECR, secret, or DNS root is destroyed.

### Saved-plan bundle

Each plan command creates a gitignored directory containing one saved plan per root, plan JSON, SHA-256 checksums, and a metadata file recording profile, direction, active account, Git commit, root order, and GitOps quiescence revision for down transitions. Apply validates that metadata and then applies each saved plan in its recorded order.

### Make operator interface

The repository-root Makefile is a thin user interface over the lifecycle wrapper. It requires an explicit `PROFILE=economical|full` for profile-aware operations and maps each target to exactly one wrapper command. `plan-up` and `plan-down` only create saved bundles; `inspect` only renders an existing bundle; `apply-up` and `apply-down` accept only an explicit `BUNDLE`.

The Makefile contains no Terraform or Kubernetes commands. This keeps resource classification and dependency ordering in the wrapper: foundation down transitions continue to set `runtime_enabled=false` so durable assets survive, while the full-profile egress root remains the only root planned with destroy mode. Make provides discoverability and shorter commands without creating a second orchestration implementation.

### Persistent-volume protection

The 2026-09-11 teardown shows the order of loss. gitops#109 merged at 18:50:58 UTC. Within a minute, the EBS CSI driver deleted the four observability volumes, because quiescence pruned their claims and the StorageClass reclaim policy is `Delete`. The Terraform plan came after that. Protection therefore has to run before quiescence, and it cannot use the Kubernetes API (FR-012).

**`snapshot-volumes`**
- It lists the volumes that the driver's IAM policy lets it create and delete, tagged `ebs.csi.aws.com/cluster` or `CSIVolumeName`, in the region of the profile's foundation roots. The foundation attaches `AmazonEBSCSIDriverPolicy`, whose conditions name exactly those tags.
- It snapshots each volume not consented away and waits for completion.
- It then writes `record.tsv` and its checksum.

**`plan down`**
- It compares the record's creation time with the committer time of the GitOps quiescence commit.
- It re-lists the volumes, so a volume created after the record blocks the plan.
- It confirms that every recorded snapshot is completed.
- It copies the record into the bundle, whose checksums cover it.

The scope is the whole region, so a snapshot may also cover a volume of another profile. That costs snapshot storage, not data.

## Constitution Check (v3.1.0)

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| Single account and environment isolation | PASS | Profiles use the existing distinct VPC/cluster roots and state keys. |
| GitOps-only deployment | PASS | The wrapper performs no Kubernetes mutation and requires external GitOps quiescence evidence before shutdown planning. |
| Declarative infrastructure | PASS | Runtime presence is a Terraform input; no resource is hidden through imperative state surgery. |
| Cost governance | PASS | Runtime-heavy resources can be removed while protected data and release assets remain. |
| Reviewed applies | PASS | Planning and applying remain separate and apply consumes only verified saved plans. |

## Verification

1. Run the new lifecycle shell contract in its required failing state.
2. Format and validate all affected Terraform roots without remote backend access.
3. Run the foundation module and root Terraform tests.
4. Run ShellCheck over the wrapper and its contract.
5. Run the existing economical and full foundation contracts.
6. Run profile preflight against the renewed AWS session; report full-profile configuration blockers without bypassing them.
7. Do not create a live plan until the address migrations and durable deletion guard have been independently reviewed.
8. Dry-run every Make target for both profiles and prove that invalid or missing profile, bundle, and GitOps revision inputs fail before invoking the wrapper.

## Risks

| Risk | Mitigation |
| --- | --- |
| Conditionalizing a singleton changes its Terraform address | Pair every such change with an explicit `moved` block and require an enabled refresh-backed no-op plan before any shutdown. |
| A shutdown deletes durable state or data | Audit saved plan JSON against a denylist and refuse apply if any durable address has a delete action. |
| Egress is removed before dependent clusters | Record and enforce inverse root order for full-profile down. |
| PersistentVolume data is lost with the cluster/VPC | Require GitOps quiescence evidence and a human review of persistent-data disposition before applying a down plan. |
| Full roots still target a retired account | Preflight each root against STS and stop; migration remains explicit separate work. |
| Make bypasses wrapper safety or hides an apply | Contract-test exact one-target-to-one-wrapper-command mappings and reject direct Terraform, kubectl, and auto-approval commands. |
| A down transition removes the VPC and with it `eco/security`'s security groups | `eco/networking` is never destroyed, and its down plan must pass the egress filter. |
| The unprotect bundle replaces or deletes the cluster | The wrapper rejects an unprotect plan that deletes anything. |
| An operator plans a persistent root through the lifecycle | The persistent roots are absent from the records, and the contract rejects any `shd` or `eco/security` path in the wrapper. |
