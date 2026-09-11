# Implementation Plan: Profile-Aware AWS Runtime Lifecycle (003)

**Branch**: `feat/profile-lifecycle` | **Date**: 2026-09-10 | **Spec**: [spec.md](./spec.md)

## Summary

Add a default-on runtime boundary to the existing foundation state instead of moving durable resources between state files. Build a profile-aware wrapper that produces saved plan bundles, validates their provenance, and applies only the reviewed artifacts. Keep GitOps quiescence as an explicit external gate.

## Design

### State-safe runtime boundary

The shared foundation module receives `runtime_enabled`. Runtime singleton resources and modules become conditional instances. Every address that changes from a singleton to index zero gets a `moved` block. Existing `for_each` addresses retain their keys and use an empty collection while disabled.

This avoids cross-state moves for write-only secret versions and protected hosted zones. It also keeps rollback simple: setting `runtime_enabled=true` recreates the runtime in the same state while all durable addresses remain unchanged.

### Profile orchestration

The wrapper owns only orchestration and evidence:

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
